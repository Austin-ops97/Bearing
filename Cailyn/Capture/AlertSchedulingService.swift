import Foundation
import UserNotifications

#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

struct AlertReceipt: Sendable {
    let identifier: String
    let kind: ActionAlertKind
    let scheduledAt: Date
    let note: String?
}

enum AlertSchedulingError: LocalizedError {
    case missingDate
    case dateInPast
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .missingDate: "Choose a date and time before scheduling an alert."
        case .dateInPast: "Choose a future date and time before scheduling an alert."
        case .permissionDenied: "Cailyn does not have permission to schedule alerts. Enable notifications or alarms in Settings."
        }
    }
}

protocol AlertScheduling: Sendable {
    func schedule(title: String, notes: String, at date: Date?, kind: ActionAlertKind) async throws -> AlertReceipt?
    func cancel(identifier: String?, kind: ActionAlertKind)
}

struct SystemAlertSchedulingService: AlertScheduling {
    func cancel(identifier: String?, kind: ActionAlertKind) {
        guard let identifier, !identifier.isEmpty else { return }
        switch kind {
        case .none:
            return
        case .reminder:
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
        case .prominentAlarm:
#if canImport(AlarmKit)
            if #available(iOS 26.0, *), let alarmID = UUID(uuidString: identifier) {
                try? AlarmManager.shared.cancel(id: alarmID)
            }
#endif
        }
    }

    func schedule(title: String, notes: String, at date: Date?, kind: ActionAlertKind) async throws -> AlertReceipt? {
        guard kind != .none else { return nil }
        guard let date else { throw AlertSchedulingError.missingDate }
        guard date > .now else { throw AlertSchedulingError.dateInPast }

        if kind == .prominentAlarm {
#if canImport(AlarmKit)
            if #available(iOS 26.0, *), let receipt = try await scheduleAlarmKit(title: title, notes: notes, at: date) {
                return receipt
            }
#endif
            let fallback = try await scheduleNotification(title: title, notes: notes, at: date)
            return AlertReceipt(identifier: fallback.identifier, kind: .reminder, scheduledAt: date, note: "Prominent alarms were unavailable, so Cailyn scheduled a standard reminder instead.")
        }
        return try await scheduleNotification(title: title, notes: notes, at: date)
    }

    private func scheduleNotification(title: String, notes: String, at date: Date) async throws -> AlertReceipt {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            authorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        guard authorized else { throw AlertSchedulingError.permissionDenied }

        let identifier = "cailyn.action.\(UUID().uuidString)"
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = notes.isEmpty ? "Cailyn action is due." : notes
        content.sound = .default
        content.categoryIdentifier = "CAILYN_ACTION_DUE"
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        return AlertReceipt(identifier: identifier, kind: .reminder, scheduledAt: date, note: nil)
    }

#if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func scheduleAlarmKit(title: String, notes: String, at date: Date) async throws -> AlertReceipt? {
        let manager = AlarmManager.shared
        var authorization = manager.authorizationState
        if authorization == .notDetermined { authorization = try await manager.requestAuthorization() }
        guard authorization == .authorized else { return nil }

        let identifier = UUID()
        let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        let alert = AlarmPresentation.Alert(title: "Cailyn", stopButton: stop)
        let presentation = AlarmPresentation(alert: alert)
        let metadata = CailynAlarmMetadata(title: title, notes: notes)
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: metadata,
            tintColor: Color(red: 0.91, green: 0.74, blue: 0.52)
        )
        let configuration = AlarmManager.AlarmConfiguration.alarm(schedule: .fixed(date), attributes: attributes)
        _ = try await manager.schedule(id: identifier, configuration: configuration)
        return AlertReceipt(identifier: identifier.uuidString, kind: .prominentAlarm, scheduledAt: date, note: nil)
    }
#endif
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct CailynAlarmMetadata: AlarmMetadata {
    let title: String
    let notes: String
}
#endif
