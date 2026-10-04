import Foundation

struct DayPlanSummary: Equatable {
    let actionCount: Int
    let eventCount: Int
    let estimatedWorkMinutes: Int
    let availableMinutes: Int

    var overCapacityMinutes: Int { max(0, estimatedWorkMinutes - availableMinutes) }
    var isFeasible: Bool { overCapacityMinutes == 0 }
}

enum WorkloadIntensity: String {
    case light = "LIGHT"
    case normal = "NORMAL"
    case heavy = "HEAVY"
    case overloaded = "OVERLOADED"
}

enum PlanningEngine {
    static func actions(_ actions: [BearingAction], on day: Date, calendar: Calendar = .current) -> [BearingAction] {
        actions.filter { action in
            guard action.status != .complete else { return false }
            if let preferredAt = action.preferredAt, calendar.isDate(preferredAt, inSameDayAs: day) { return true }
            if let dueAt = action.dueAt, calendar.isDate(dueAt, inSameDayAs: day) { return true }
            return action.priority == .today && calendar.isDateInToday(day)
        }
    }

    static func events(_ events: [BearingCalendarEvent], on day: Date, calendar: Calendar = .current) -> [BearingCalendarEvent] {
        events.filter { calendar.isDate($0.startAt, inSameDayAs: day) }.sorted { $0.startAt < $1.startAt }
    }

    static func summary(
        actions: [BearingAction],
        events: [BearingCalendarEvent],
        on day: Date,
        availableMinutes: Int = 8 * 60,
        calendar: Calendar = .current
    ) -> DayPlanSummary {
        let dayActions = self.actions(actions, on: day, calendar: calendar)
        let dayEvents = self.events(events, on: day, calendar: calendar)
        let actionMinutes = dayActions.reduce(0) { $0 + ($1.estimatedDurationMinutes ?? 30) }
        let eventMinutes = dayEvents.reduce(0) { partial, event in
            partial + max(0, Int(event.endAt.timeIntervalSince(event.startAt) / 60)) + event.preparationMinutes + event.transitionMinutes
        }
        return DayPlanSummary(
            actionCount: dayActions.count,
            eventCount: dayEvents.count,
            estimatedWorkMinutes: actionMinutes + eventMinutes,
            availableMinutes: availableMinutes
        )
    }

    static func intensity(for summary: DayPlanSummary) -> WorkloadIntensity {
        guard summary.availableMinutes > 0 else { return .overloaded }
        let utilization = Double(summary.estimatedWorkMinutes) / Double(summary.availableMinutes)
        switch utilization {
        case ..<0.4: return .light
        case ..<0.75: return .normal
        case ...1.0: return .heavy
        default: return .overloaded
        }
    }

    static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }
}
