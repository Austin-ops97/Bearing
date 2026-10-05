import Foundation
import SwiftData

enum LegacyDemoDataCleanup {
    @MainActor
    static func removeLegacySamples(in context: ModelContext) throws {
        let actions = try context.fetch(FetchDescriptor<CailynAction>())
        let people = try context.fetch(FetchDescriptor<CailynPerson>())
        let assets = try context.fetch(FetchDescriptor<CailynAsset>())
        let events = try context.fetch(FetchDescriptor<CailynCalendarEvent>())
        let routines = try context.fetch(FetchDescriptor<CailynRoutine>())

        let sampleActions = actions.filter(isLegacySampleAction)
        let samplePeople = people.filter(isLegacySamplePerson)
        let sampleAssets = assets.filter(isLegacySampleAsset)
        let sampleEvents = events.filter(isLegacySampleEvent)
        let sampleRoutines = routines.filter(isLegacySampleRoutine)
        let sampleActionIDs = Set(sampleActions.map(\.id))
        let sampleAssetIDs = Set(sampleAssets.map(\.id))
        let hasLegacySampleData = !sampleActions.isEmpty || !samplePeople.isEmpty
            || !sampleAssets.isEmpty || !sampleEvents.isEmpty || !sampleRoutines.isEmpty

        for action in sampleActions {
            context.delete(action)
        }
        for event in sampleEvents {
            context.delete(event)
        }
        for routine in sampleRoutines {
            context.delete(routine)
        }
        for entry in try context.fetch(FetchDescriptor<CailynLogEntry>()) {
            let isSeededLog: Bool
            switch entry.text {
            case "Shift started":
                let time = Calendar.current.dateComponents([.hour, .minute], from: entry.timestamp)
                isSeededLog = hasLegacySampleData
                    && entry.kind == .manual
                    && time.hour == 6
                    && time.minute == 3
            case "Yankee 3 verified — requires attention", "PHR 6 verified available",
                 "Dickerson 1 verified running":
                isSeededLog = entry.assetID.map(sampleAssetIDs.contains) ?? false
            case "Yankee charger follow-up created":
                isSeededLog = entry.actionID.map(sampleActionIDs.contains) ?? false
            default:
                isSeededLog = false
            }
            if isSeededLog { context.delete(entry) }
        }
        for person in samplePeople {
            context.delete(person)
        }
        for asset in sampleAssets {
            context.delete(asset)
        }
        try context.save()
    }

    private static func isLegacySamplePerson(_ person: CailynPerson) -> Bool {
        (person.displayName == "Mike Thompson"
            && person.email == "mike@example.com"
            && person.organization == "Operations"
            && person.role == "Maintenance Lead")
            || (person.displayName == "Sarah Jenkins"
                && person.email == "sarah@example.com"
                && person.organization == "Operations"
                && person.role == "Operations Manager")
    }

    private static func isLegacySampleAsset(_ asset: CailynAsset) -> Bool {
        guard asset.area == "Fleet", asset.lastChecked != nil, asset.nextCheck == nil else { return false }
        return switch asset.name {
        case "Yankee 3":
            asset.category == "Unit" && asset.status == .attention && asset.details == "Battery charger issue"
        case "PHR 6", "Dickerson 1":
            asset.category == "Unit" && asset.status == .normal && asset.details.isEmpty
        case "Ellwood":
            asset.category == "Site" && asset.status == .normal && asset.details.isEmpty
        default:
            false
        }
    }

    private static func isLegacySampleEvent(_ event: CailynCalendarEvent) -> Bool {
        guard event.source == .cailyn, event.location == nil, event.notes.isEmpty,
              event.transitionMinutes == 0 else { return false }
        let start = Calendar.current.dateComponents([.hour, .minute], from: event.startAt)
        let duration = event.endAt.timeIntervalSince(event.startAt)
        return switch event.title {
        case "Shift Turnover":
            start.hour == 7 && start.minute == 0 && duration == 30 * 60 && event.preparationMinutes == 0
        case "Unit Checks":
            start.hour == 8 && start.minute == 30 && duration == 30 * 60 && event.preparationMinutes == 0
        case "Operations Meeting":
            start.hour == 9 && start.minute == 30 && duration == 60 * 60 && event.preparationMinutes == 20
        case "Rounds":
            start.hour == 12 && start.minute == 0 && duration == 30 * 60 && event.preparationMinutes == 0
        default:
            false
        }
    }

    private static func isLegacySampleRoutine(_ routine: CailynRoutine) -> Bool {
        routine.title == "Start of Shift"
            && routine.scheduleDescription == "Daily at shift start"
            && Set(routine.items.map(\.title)) == [
                "Review turnover", "Check unit status", "Check active alarms",
                "Review commitments", "Review follow-ups"
            ]
            && routine.items.count == 5
    }

    private static func isLegacySampleAction(_ action: CailynAction) -> Bool {
        guard action.details.isEmpty else { return false }
        return switch action.title {
        case "Battery charger follow-up":
            action.priority == .immediate
                && action.status == .open
                && action.source == nil
                && action.estimatedDurationMinutes == 10
                && action.timing == .deadline
                && action.person?.displayName == "Mike Thompson"
                && action.asset?.name == "Yankee 3"
        case "Confirm dispatch schedule":
            action.priority == .today
                && action.status == .open
                && action.source == nil
                && action.estimatedDurationMinutes == 8
                && action.timing == .deadline
                && action.asset?.name == "Dickerson 1"
        case "Valve PO documentation":
            action.priority == .today
                && action.status == .open
                && action.source == "Email Maintenance"
                && action.estimatedDurationMinutes == 35
                && action.timing == .flexible
        case "Valve confirmation":
            action.priority == .today
                && action.status == .waiting
                && action.source == nil
                && action.person?.displayName == "Mike Thompson"
        case "Outage approval":
            action.priority == .planned
                && action.status == .waiting
                && action.source == nil
                && action.person?.displayName == "Sarah Jenkins"
        default:
            false
        }
    }
}
