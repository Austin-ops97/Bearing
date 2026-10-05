import Foundation

enum AttentionEngine {
    static func requiresAttention(_ action: CailynAction, now: Date = .now) -> Bool {
        guard action.status != .complete else { return false }

        if action.priority == .immediate { return true }
        if let dueAt = action.dueAt, dueAt <= now { return true }
        if action.status == .waiting, let followUpAt = action.followUpAt, followUpAt <= now { return true }
        return false
    }

    static func rank(_ lhs: CailynAction, _ rhs: CailynAction, now: Date = .now) -> Bool {
        let lhsAttention = requiresAttention(lhs, now: now)
        let rhsAttention = requiresAttention(rhs, now: now)
        if lhsAttention != rhsAttention { return lhsAttention }
        if lhs.priorityRaw != rhs.priorityRaw { return lhs.priorityRaw < rhs.priorityRaw }
        return (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture)
    }

    static func waitingDuration(from date: Date, to now: Date = .now, calendar: Calendar = .current) -> String {
        let days = max(0, calendar.dateComponents([.day], from: date, to: now).day ?? 0)
        if days == 0 { return "today" }
        return days == 1 ? "1 day" : "\(days) days"
    }
}

