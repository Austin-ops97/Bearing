import Foundation
import SwiftUI
import UIKit
import MSAL

struct MicrosoftGraphEvent: Decodable, Identifiable, Sendable {
    let id: String
    let subject: String?
    let start: DateTimeTimeZone
    let end: DateTimeTimeZone
    let location: EventLocation?
    let onlineMeeting: OnlineMeeting?
    let webLink: String?

    struct DateTimeTimeZone: Decodable, Sendable {
        let dateTime: String
        let timeZone: String
    }

    struct EventLocation: Decodable, Sendable {
        let displayName: String?
    }

    struct OnlineMeeting: Decodable, Sendable {
        let joinUrl: String?
    }
}

struct MicrosoftGraphMessage: Decodable, Identifiable, Sendable {
    let id: String
    let subject: String?
    let from: Recipient?
    let receivedDateTime: Date?
    let importance: String?
    let isRead: Bool?
    let bodyPreview: String?
    let webLink: String?
    let flag: Flag?

    struct Recipient: Decodable, Sendable {
        let emailAddress: EmailAddress
    }

    struct EmailAddress: Decodable, Sendable {
        let name: String?
        let address: String?
    }

    struct Flag: Decodable, Sendable {
        let flagStatus: String?
    }

    var deterministicPriority: Int {
        var score = 0
        if importance?.caseInsensitiveCompare("high") == .orderedSame { score += 4 }
        if flag?.flagStatus?.caseInsensitiveCompare("flagged") == .orderedSame { score += 3 }
        if isRead == false { score += 1 }
        let subject = (subject ?? "").lowercased()
        if ["urgent", "action required", "deadline", "escalation", "outage", "incident"].contains(where: subject.contains) {
            score += 3
        }
        return score
    }

    var priorityLabel: String {
        deterministicPriority >= 4 ? "High Priority" : deterministicPriority >= 2 ? "Review" : "Standard"
    }
}

@MainActor
final class MicrosoftGraphService: ObservableObject {
    static let shared = MicrosoftGraphService()
    static let clientID = "SET_MICROSOFT_ENTRA_CLIENT_ID"
    static let redirectURI = "msauth.com.austinops97.Cailyn://auth"
    private static let authorityURL = URL(string: "https://login.microsoftonline.com/organizations")!
    private static let loginScopes = ["User.Read", "Calendars.Read", "Mail.Read"]

    @Published private(set) var accountName: String?
    @Published private(set) var accountEmail: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var events: [MicrosoftGraphEvent] = []
    @Published private(set) var messages: [MicrosoftGraphMessage] = []
    @Published var senderPriorityRules: String {
        didSet { UserDefaults.standard.set(senderPriorityRules, forKey: "microsoft.senderPriorityRules") }
    }
    @Published var keywordPriorityRules: String {
        didSet { UserDefaults.standard.set(keywordPriorityRules, forKey: "microsoft.keywordPriorityRules") }
    }
    @Published private(set) var isRefreshing = false
    @Published private(set) var isConfigured: Bool

    private var application: MSALPublicClientApplication?
    private var account: MSALAccount?

    private init() {
        isConfigured = Self.clientID != "SET_MICROSOFT_ENTRA_CLIENT_ID"
        senderPriorityRules = UserDefaults.standard.string(forKey: "microsoft.senderPriorityRules") ?? ""
        keywordPriorityRules = UserDefaults.standard.string(forKey: "microsoft.keywordPriorityRules") ?? "urgent\naction required\ndeadline\nescalation\noutage\nincident"
        do {
            application = try makeApplication()
            if let identifier = UserDefaults.standard.string(forKey: "microsoft.homeAccountIdentifier") {
                account = try application?.account(forIdentifier: identifier)
                accountName = account?.username
                accountEmail = account?.username
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var isConnected: Bool { account != nil }
    var prioritizedMessages: [MicrosoftGraphMessage] {
        messages.map { message in
            (message, priorityScore(for: message))
        }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    func priorityScore(for message: MicrosoftGraphMessage) -> Int {
        var score = message.deterministicPriority
        let senderRules = senderPriorityRules.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let address = message.from?.emailAddress.address?.lowercased() ?? ""
        let name = message.from?.emailAddress.name?.lowercased() ?? ""
        if senderRules.contains(where: { !$0.isEmpty && (address.contains($0) || name.contains($0)) }) {
            score += 5
        }
        let keywordRules = keywordPriorityRules.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let searchable = "\(message.subject ?? "") \(message.bodyPreview ?? "")".lowercased()
        if keywordRules.contains(where: { !$0.isEmpty && searchable.contains($0) }) {
            score += 3
        }
        return score
    }

    func connect() async {
        guard isConfigured else {
            errorMessage = "Microsoft sign-in is not configured yet. Register Cailyn in Microsoft Entra ID and provide its public client ID."
            return
        }
        do {
            let application = try makeApplication()
            self.application = application
            guard let presenter = await Self.presentationViewController() else {
                throw MicrosoftGraphError.noPresentationController
            }
            let parameters = MSALInteractiveTokenParameters(
                scopes: Self.loginScopes,
                webviewParameters: MSALWebviewParameters(authPresentationViewController: presenter)
            )
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MSALResult, Error>) in
                application.acquireToken(with: parameters) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: MicrosoftGraphError.emptyAuthenticationResponse)
                    }
                }
            }
            account = result.account
            accountName = result.account.username
            accountEmail = result.account.username
            UserDefaults.standard.set(
                result.account.homeAccountId?.identifier,
                forKey: "microsoft.homeAccountIdentifier"
            )
            errorMessage = nil
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() async {
        do {
            if let application, let account {
                try application.remove(account)
            }
            account = nil
            accountName = nil
            accountEmail = nil
            events = []
            messages = []
            UserDefaults.standard.removeObject(forKey: "microsoft.homeAccountIdentifier")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard let account, let application else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let token = try await accessToken(for: account, application: application)
            let calendar = try await graphRequest(
                path: "/me/calendarView?startDateTime=\(Self.utcOffset(-14))&endDateTime=\(Self.utcOffset(60))&$select=id,subject,start,end,location,onlineMeeting,webLink&$orderby=start/dateTime&$top=100",
                token: token,
                as: MicrosoftGraphCollection<MicrosoftGraphEvent>.self
            )
            let mail = try await graphRequest(
                path: "/me/messages?$select=id,subject,from,receivedDateTime,importance,isRead,bodyPreview,webLink,flag&$orderby=receivedDateTime%20desc&$top=100",
                token: token,
                as: MicrosoftGraphCollection<MicrosoftGraphMessage>.self
            )
            events = calendar.value
            messages = mail.value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func accessToken(for account: MSALAccount, application: MSALPublicClientApplication) async throws -> String {
        let parameters = MSALSilentTokenParameters(scopes: Self.loginScopes, account: account)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            application.acquireTokenSilent(with: parameters) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token = result?.accessToken {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: MicrosoftGraphError.emptyAuthenticationResponse)
                }
            }
        }
    }

    private func graphRequest<Value: Decodable>(path: String, token: String, as type: Value.Type) async throws -> Value {
        var components = URLComponents(string: "https://graph.microsoft.com/v1.0")!
        if let queryStart = path.firstIndex(of: "?") {
            components.path = String(path[..<queryStart])
            components.percentEncodedQuery = String(path[path.index(after: queryStart)...])
        } else {
            components.path = path
        }
        guard let url = components.url else { throw MicrosoftGraphError.invalidRequest }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MicrosoftGraphError.invalidRequest }
        guard (200..<300).contains(http.statusCode) else {
            throw MicrosoftGraphError.graphRequestFailed("Microsoft Graph returned HTTP \(http.statusCode).")
        }
        return try JSONDecoder.microsoftGraph.decode(type, from: data)
    }

    private func makeApplication() throws -> MSALPublicClientApplication {
        let authority = try MSALAADAuthority(url: Self.authorityURL)
        let configuration = MSALPublicClientApplicationConfig(
            clientId: Self.clientID,
            redirectUri: Self.redirectURI,
            authority: authority
        )
        return try MSALPublicClientApplication(configuration: configuration)
    }

    private static func presentationViewController() async -> UIViewController? {
        await MainActor.run {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController
        }
    }

    private static func utcOffset(_ days: Int) -> String {
        ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: days, to: .now)!)
    }
}

private struct MicrosoftGraphCollection<Element: Decodable>: Decodable {
    let value: [Element]
}

private enum MicrosoftGraphError: LocalizedError {
    case noPresentationController
    case emptyAuthenticationResponse
    case notConnected
    case invalidRequest
    case graphRequestFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPresentationController: "Unable to display Microsoft sign-in because no active application window is available."
        case .emptyAuthenticationResponse: "Microsoft sign-in returned no token or account."
        case .notConnected: "Connect your Microsoft 365 account before using linked work records."
        case .invalidRequest: "The Microsoft Graph request could not be created."
        case .graphRequestFailed(let message): message
        }
    }
}

private extension JSONDecoder {
    static var microsoftGraph: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
