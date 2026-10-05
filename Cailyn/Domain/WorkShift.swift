import Foundation

enum WorkShift: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case day
    case night

    var id: String { rawValue }
    var title: String { rawValue.capitalized + " Shift" }

    var routineDefaults: [String] {
        switch self {
        case .day:
            [
                "Review overnight turnover and open actions",
                "Check unit and asset status",
                "Review alarms and scheduled work",
                "Confirm staffing and day priorities",
                "Prepare end-of-shift handoff"
            ]
        case .night:
            [
                "Review day-shift turnover and open actions",
                "Check unit and asset status",
                "Review alarms and overnight work",
                "Confirm on-call contacts and escalations",
                "Prepare morning handoff"
            ]
        }
    }
}

enum ShiftAssignment: String, CaseIterable, Hashable, Identifiable {
    case automatic
    case day
    case night

    var id: String { rawValue }

    var shift: WorkShift? {
        switch self {
        case .automatic: nil
        case .day: .day
        case .night: .night
        }
    }

    static func automatic(for date: Date, schedule: ShiftSchedule = .stored) -> Self {
        switch schedule.shift(containing: date) {
        case .day: .day
        case .night: .night
        case nil: .automatic
        }
    }
}

struct ShiftSchedule: Equatable, Sendable {
    static let dayStartKey = "schedule.dayStartMinute"
    static let dayEndKey = "schedule.dayEndMinute"
    static let nightStartKey = "schedule.nightStartMinute"
    static let nightEndKey = "schedule.nightEndMinute"

    var dayStartMinute: Int
    var dayEndMinute: Int
    var nightStartMinute: Int
    var nightEndMinute: Int

    static let standard = ShiftSchedule(
        dayStartMinute: 5 * 60,
        dayEndMinute: 17 * 60,
        nightStartMinute: 17 * 60,
        nightEndMinute: 5 * 60
    )

    static var stored: Self {
        let defaults = UserDefaults.standard
        return ShiftSchedule(
            dayStartMinute: defaults.object(forKey: dayStartKey) as? Int ?? standard.dayStartMinute,
            dayEndMinute: defaults.object(forKey: dayEndKey) as? Int ?? standard.dayEndMinute,
            nightStartMinute: defaults.object(forKey: nightStartKey) as? Int ?? standard.nightStartMinute,
            nightEndMinute: defaults.object(forKey: nightEndKey) as? Int ?? standard.nightEndMinute
        )
    }

    func shift(containing date: Date, calendar: Calendar = .current) -> WorkShift? {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if contains(minute, start: dayStartMinute, end: dayEndMinute) { return .day }
        if contains(minute, start: nightStartMinute, end: nightEndMinute) { return .night }
        return nil
    }

    func interval(for shift: WorkShift, containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        let startMinute = shift == .day ? dayStartMinute : nightStartMinute
        let endMinute = shift == .day ? dayEndMinute : nightEndMinute
        let isOvernight = endMinute <= startMinute
        let endHour = endMinute / 60
        let endMinutePart = endMinute % 60
        let startDate: Date

        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if isOvernight, minute < endMinute {
            startDate = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        } else {
            startDate = date
        }

        guard let start = calendar.date(
            bySettingHour: (shift == .day ? dayStartMinute : nightStartMinute) / 60,
            minute: (shift == .day ? dayStartMinute : nightStartMinute) % 60,
            second: 0,
            of: startDate
        ), let end = calendar.date(
            bySettingHour: endHour,
            minute: endMinutePart,
            second: 0,
            of: isOvernight ? (calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate) : startDate
        ), end > start else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    func label(for shift: WorkShift) -> String {
        let start = shift == .day ? dayStartMinute : nightStartMinute
        let end = shift == .day ? dayEndMinute : nightEndMinute
        return "\(shift.title) · \(Self.time(start))–\(Self.time(end))"
    }

    private func contains(_ minute: Int, start: Int, end: Int) -> Bool {
        guard start != end else { return false }
        if end > start { return minute >= start && minute < end }
        return minute >= start || minute < end
    }

    private static func time(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}
