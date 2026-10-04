import Foundation
import SwiftData

enum DemoContent {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
#if DEBUG
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: .now)
        func today(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(byAdding: .minute, value: hour * 60 + minute, to: startOfDay) ?? .now
        }

        let descriptor = FetchDescriptor<BearingAction>()
        if (try? context.fetchCount(descriptor)) == 0 {

        let mike = BearingPerson(displayName: "Mike Thompson", email: "mike@example.com", organization: "Operations", role: "Maintenance Lead")
        let sarah = BearingPerson(displayName: "Sarah Jenkins", email: "sarah@example.com", organization: "Operations", role: "Operations Manager")
        let yankee = BearingAsset(name: "Yankee 3", category: "Unit", area: "Fleet", status: .attention, details: "Battery charger issue", lastChecked: today(6, 14))
        let phr = BearingAsset(name: "PHR 6", category: "Unit", area: "Fleet", status: .normal, lastChecked: today(6, 17))
        let dickerson = BearingAsset(name: "Dickerson 1", category: "Unit", area: "Fleet", status: .normal, lastChecked: today(6, 22))
        let ellwood = BearingAsset(name: "Ellwood", category: "Site", area: "Fleet", status: .normal, lastChecked: today(6, 28))

        context.insert(mike)
        context.insert(sarah)
        context.insert(yankee)
        context.insert(phr)
        context.insert(dickerson)
        context.insert(ellwood)

        let charger = BearingAction(title: "Battery charger follow-up", priority: .immediate, dueAt: calendar.date(byAdding: .hour, value: -2, to: .now), estimatedDurationMinutes: 10, timing: .deadline, person: mike, asset: yankee)
        let dispatch = BearingAction(title: "Confirm dispatch schedule", priority: .today, dueAt: today(8, 30), estimatedDurationMinutes: 8, timing: .deadline, asset: dickerson)
        let documentation = BearingAction(title: "Valve PO documentation", priority: .today, dueAt: today(10), estimatedDurationMinutes: 35, timing: .flexible, source: "Email Maintenance")
        let valve = BearingAction(title: "Valve confirmation", priority: .today, status: .waiting, followUpAt: today(8), waitingSince: calendar.date(byAdding: .day, value: -2, to: .now), person: mike)
        let outage = BearingAction(title: "Outage approval", priority: .planned, status: .waiting, followUpAt: calendar.date(byAdding: .day, value: 1, to: .now), waitingSince: calendar.date(byAdding: .day, value: -1, to: .now), person: sarah)
        [charger, dispatch, documentation, valve, outage].forEach(context.insert)

        let routineItems = ["Review turnover", "Check unit status", "Check active alarms", "Review commitments", "Review follow-ups"].enumerated().map {
            BearingRoutineItem(title: $0.element, sortOrder: $0.offset)
        }
        let routine = BearingRoutine(title: "Start of Shift", scheduleDescription: "Daily at shift start", nextDue: today(7), items: routineItems)
        context.insert(routine)

        [
            BearingLogEntry(timestamp: today(6, 3), text: "Shift started", kind: .manual),
            BearingLogEntry(timestamp: today(6, 14), text: "Yankee 3 verified — requires attention", kind: .asset, assetID: yankee.id),
            BearingLogEntry(timestamp: today(6, 17), text: "PHR 6 verified available", kind: .asset, assetID: phr.id),
            BearingLogEntry(timestamp: today(6, 22), text: "Dickerson 1 verified running", kind: .asset, assetID: dickerson.id),
            BearingLogEntry(timestamp: today(6, 41), text: "Yankee charger follow-up created", kind: .action, actionID: charger.id)
        ].forEach(context.insert)

        try? context.save()
        }

        let eventDescriptor = FetchDescriptor<BearingCalendarEvent>()
        if (try? context.fetchCount(eventDescriptor)) == 0 {
            [
                BearingCalendarEvent(title: "Shift Turnover", startAt: today(7), endAt: today(7, 30)),
                BearingCalendarEvent(title: "Unit Checks", startAt: today(8, 30), endAt: today(9)),
                BearingCalendarEvent(title: "Operations Meeting", startAt: today(9, 30), endAt: today(10, 30), preparationMinutes: 20),
                BearingCalendarEvent(title: "Rounds", startAt: today(12), endAt: today(12, 30))
            ].forEach(context.insert)
            try? context.save()
        }
#endif
    }
}
