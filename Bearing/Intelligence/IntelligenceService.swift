import Foundation

struct CaptureProposal: Equatable {
    var title: String
    var personName: String?
    var assetName: String?
    var dueAt: Date?
    var priority: ActionPriority
    var status: ActionStatus
    var confidence: Double
    var originalText: String
}

protocol IntelligenceService: Sendable {
    func proposeAction(from text: String, people: [String], assets: [String], now: Date) async -> CaptureProposal
}

struct LocalRuleIntelligenceService: IntelligenceService {
    func proposeAction(from text: String, people: [String], assets: [String], now: Date = .now) async -> CaptureProposal {
        let lower = text.lowercased()
        let person = people.first { lower.contains($0.lowercased().split(separator: " ").first.map(String.init) ?? $0.lowercased()) }
        let asset = assets.first { lower.contains($0.lowercased()) }
        let date = Self.detectDate(in: lower, now: now)
        let isWaiting = lower.contains("waiting") || lower.contains("check with") || lower.contains("follow up")
        let immediate = lower.contains("urgent") || lower.contains("immediately")

        var title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.last == "." { title.removeLast() }
        title = title.prefix(1).uppercased() + title.dropFirst()

        let extracted = [person != nil, asset != nil, date != nil].filter { $0 }.count
        return CaptureProposal(
            title: title,
            personName: person,
            assetName: asset,
            dueAt: date,
            priority: immediate ? .immediate : (date != nil ? .today : .planned),
            status: isWaiting ? .waiting : .open,
            confidence: 0.58 + Double(extracted) * 0.1,
            originalText: text
        )
    }

    private static func detectDate(in text: String, now: Date) -> Date? {
        let calendar = Calendar.current
        if text.contains("today") { return now }
        if text.contains("tomorrow") { return calendar.date(byAdding: .day, value: 1, to: now) }

        let symbols = calendar.weekdaySymbols.map { $0.lowercased() }
        guard let targetIndex = symbols.firstIndex(where: text.contains) else { return nil }
        let targetWeekday = targetIndex + 1
        let currentWeekday = calendar.component(.weekday, from: now)
        var days = (targetWeekday - currentWeekday + 7) % 7
        if days == 0 { days = 7 }
        return calendar.date(byAdding: .day, value: days, to: now)
    }
}
