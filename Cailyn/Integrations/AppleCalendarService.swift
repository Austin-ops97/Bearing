import EventKit
import Foundation
import UIKit

enum AppleCalendarError: LocalizedError {
    case accessDenied
    case noWritableSource

    var errorDescription: String? {
        switch self {
        case .accessDenied: "Calendar access was not granted. Enable Cailyn in Settings → Privacy & Security → Calendars."
        case .noWritableSource: "No writable iOS calendar account is available on this device."
        }
    }
}

@MainActor
final class AppleCalendarService {
    static let shared = AppleCalendarService()
    private let store = EKEventStore()
    private let calendarTitle = "Cailyn"

    func saveEvent(identifier: String?, title: String, start: Date, end: Date, location: String?, notes: String) async throws -> String {
        let authorized = try await store.requestWriteOnlyAccessToEvents()
        guard authorized else { throw AppleCalendarError.accessDenied }
        let event: EKEvent
        if let identifier, let existing = store.event(withIdentifier: identifier) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = try cailynCalendar()
        }
        event.title = title
        event.startDate = start
        event.endDate = end
        event.location = location
        event.notes = notes
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    func deleteEvent(identifier: String) async throws {
        let authorized = try await store.requestWriteOnlyAccessToEvents()
        guard authorized else { throw AppleCalendarError.accessDenied }
        guard let event = store.event(withIdentifier: identifier) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    private func cailynCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == calendarTitle && $0.allowsContentModifications }) {
            return existing
        }
        guard let source = store.defaultCalendarForNewEvents?.source ?? store.sources.first(where: { $0.sourceType == .local }) else {
            throw AppleCalendarError.noWritableSource
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarTitle
        calendar.source = source
        calendar.cgColor = UIColor(red: 0.91, green: 0.74, blue: 0.52, alpha: 1).cgColor
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }
}
