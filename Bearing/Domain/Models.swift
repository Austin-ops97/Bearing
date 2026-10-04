import Foundation
import SwiftData

enum BearingSchema {
    static let models: [any PersistentModel.Type] = [
        BearingAction.self,
        BearingPerson.self,
        BearingAsset.self,
        BearingCalendarEvent.self,
        BearingLogEntry.self,
        BearingRoutine.self,
        BearingRoutineItem.self
    ]
}

enum ActionPriority: Int, Codable, CaseIterable, Identifiable {
    case immediate = 1
    case today = 2
    case planned = 3
    case reference = 4

    var id: Int { rawValue }
    var code: String { "P\(rawValue)" }
    var label: String {
        switch self {
        case .immediate: "Immediate"
        case .today: "Today"
        case .planned: "Planned"
        case .reference: "Reference"
        }
    }
}

enum ActionStatus: String, Codable, CaseIterable, Identifiable {
    case open
    case active
    case waiting
    case complete

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

enum TimingClassification: String, Codable, CaseIterable, Identifiable {
    case fixed
    case deadline
    case flexible
    case someday

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

enum AssetStatus: String, Codable, CaseIterable {
    case normal
    case attention
    case unavailable
    case unknown

    var label: String {
        switch self {
        case .normal: "NORMAL"
        case .attention: "REQUIRES ATTENTION"
        case .unavailable: "UNAVAILABLE"
        case .unknown: "UNKNOWN"
        }
    }
}

@Model
final class BearingAction {
    var id: UUID
    var title: String
    var details: String
    var priorityRaw: Int
    var statusRaw: String
    var dueAt: Date?
    var preferredAt: Date?
    var estimatedDurationMinutes: Int?
    var actualDurationMinutes: Int?
    var timingRaw: String
    var followUpAt: Date?
    var waitingSince: Date?
    var createdAt: Date
    var modifiedAt: Date
    var completedAt: Date?
    var source: String?
    var location: String?
    var person: BearingPerson?
    var asset: BearingAsset?

    var priority: ActionPriority {
        get { ActionPriority(rawValue: priorityRaw) ?? .planned }
        set { priorityRaw = newValue.rawValue }
    }

    var status: ActionStatus {
        get { ActionStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    var timing: TimingClassification {
        get { TimingClassification(rawValue: timingRaw) ?? .flexible }
        set { timingRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        priority: ActionPriority = .planned,
        status: ActionStatus = .open,
        dueAt: Date? = nil,
        preferredAt: Date? = nil,
        estimatedDurationMinutes: Int? = nil,
        actualDurationMinutes: Int? = nil,
        timing: TimingClassification = .flexible,
        followUpAt: Date? = nil,
        waitingSince: Date? = nil,
        source: String? = nil,
        location: String? = nil,
        person: BearingPerson? = nil,
        asset: BearingAsset? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.priorityRaw = priority.rawValue
        self.statusRaw = status.rawValue
        self.dueAt = dueAt
        self.preferredAt = preferredAt
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.actualDurationMinutes = actualDurationMinutes
        self.timingRaw = timing.rawValue
        self.followUpAt = followUpAt
        self.waitingSince = waitingSince
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.source = source
        self.location = location
        self.person = person
        self.asset = asset
    }

    func complete(at date: Date = .now) {
        status = .complete
        completedAt = date
        modifiedAt = date
    }

    func markWaiting(on person: BearingPerson?, followUpAt: Date?, date: Date = .now) {
        self.person = person
        self.followUpAt = followUpAt
        waitingSince = date
        status = .waiting
        modifiedAt = date
    }
}

enum CalendarEventSource: String, Codable, CaseIterable {
    case bearing
    case appleCalendar
    case microsoftGraph

    var label: String {
        switch self {
        case .bearing: "BEARING"
        case .appleCalendar: "APPLE CALENDAR"
        case .microsoftGraph: "MICROSOFT 365"
        }
    }
}

@Model
final class BearingCalendarEvent {
    var id: UUID
    var title: String
    var startAt: Date
    var endAt: Date
    var preparationMinutes: Int
    var transitionMinutes: Int
    var sourceRaw: String
    var externalID: String?
    var location: String?
    var notes: String

    var source: CalendarEventSource {
        get { CalendarEventSource(rawValue: sourceRaw) ?? .bearing }
        set { sourceRaw = newValue.rawValue }
    }

    var occupiedInterval: DateInterval {
        DateInterval(
            start: startAt.addingTimeInterval(TimeInterval(-(preparationMinutes + transitionMinutes) * 60)),
            end: endAt
        )
    }

    init(
        id: UUID = UUID(),
        title: String,
        startAt: Date,
        endAt: Date,
        preparationMinutes: Int = 0,
        transitionMinutes: Int = 0,
        source: CalendarEventSource = .bearing,
        externalID: String? = nil,
        location: String? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.preparationMinutes = preparationMinutes
        self.transitionMinutes = transitionMinutes
        self.sourceRaw = source.rawValue
        self.externalID = externalID
        self.location = location
        self.notes = notes
    }
}

@Model
final class BearingPerson {
    var id: UUID
    var displayName: String
    var email: String?
    var phone: String?
    var organization: String?
    var role: String?
    var appleContactID: String?
    var microsoftContactID: String?
    var notes: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \BearingAction.person)
    var actions: [BearingAction]

    init(
        id: UUID = UUID(),
        displayName: String,
        email: String? = nil,
        phone: String? = nil,
        organization: String? = nil,
        role: String? = nil,
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.phone = phone
        self.organization = organization
        self.role = role
        self.notes = notes
        self.createdAt = createdAt
        self.actions = []
    }
}

@Model
final class BearingAsset {
    var id: UUID
    var name: String
    var category: String
    var area: String
    var statusRaw: String
    var details: String
    var lastChecked: Date?
    var nextCheck: Date?
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \BearingAction.asset)
    var actions: [BearingAction]

    var status: AssetStatus {
        get { AssetStatus(rawValue: statusRaw) ?? .unknown }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        category: String,
        area: String = "Operations",
        status: AssetStatus = .normal,
        details: String = "",
        lastChecked: Date? = nil,
        nextCheck: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.area = area
        self.statusRaw = status.rawValue
        self.details = details
        self.lastChecked = lastChecked
        self.nextCheck = nextCheck
        self.createdAt = createdAt
        self.actions = []
    }
}

enum LogEntryKind: String, Codable, CaseIterable {
    case manual
    case action
    case asset
    case routine
    case system
}

@Model
final class BearingLogEntry {
    var id: UUID
    var timestamp: Date
    var text: String
    var kindRaw: String
    var actionID: UUID?
    var personID: UUID?
    var assetID: UUID?

    var kind: LogEntryKind {
        get { LogEntryKind(rawValue: kindRaw) ?? .manual }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        text: String,
        kind: LogEntryKind = .manual,
        actionID: UUID? = nil,
        personID: UUID? = nil,
        assetID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.kindRaw = kind.rawValue
        self.actionID = actionID
        self.personID = personID
        self.assetID = assetID
    }
}

@Model
final class BearingRoutine {
    var id: UUID
    var title: String
    var scheduleDescription: String
    var nextDue: Date?
    var lastCompleted: Date?
    var isEnabled: Bool

    @Relationship(deleteRule: .cascade, inverse: \BearingRoutineItem.routine)
    var items: [BearingRoutineItem]

    init(
        id: UUID = UUID(),
        title: String,
        scheduleDescription: String,
        nextDue: Date? = nil,
        lastCompleted: Date? = nil,
        isEnabled: Bool = true,
        items: [BearingRoutineItem] = []
    ) {
        self.id = id
        self.title = title
        self.scheduleDescription = scheduleDescription
        self.nextDue = nextDue
        self.lastCompleted = lastCompleted
        self.isEnabled = isEnabled
        self.items = items
    }
}

@Model
final class BearingRoutineItem {
    var id: UUID
    var title: String
    var sortOrder: Int
    var completedAt: Date?
    var routine: BearingRoutine?

    init(id: UUID = UUID(), title: String, sortOrder: Int, completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.sortOrder = sortOrder
        self.completedAt = completedAt
    }
}
