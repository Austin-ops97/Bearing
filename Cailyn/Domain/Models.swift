import Foundation
import SwiftData

enum CailynSchema {
    static let models: [any PersistentModel.Type] = [
        CailynAction.self,
        CailynPerson.self,
        CailynAsset.self,
        CailynCalendarEvent.self,
        CailynLogEntry.self,
        CailynRoutine.self,
        CailynRoutineItem.self,
        CailynTurnoverNote.self,
        CailynTemplate.self,
        CailynKnowledgeItem.self,
        CailynKnowledgeFolder.self,
        CailynKnowledgeDocument.self,
        CailynKnowledgeChunk.self,
        CailynReminder.self
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
final class CailynAction {
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
    var alertKindRaw: String?
    var alertIdentifier: String?
    var alertScheduledAt: Date?
    var person: CailynPerson?
    var asset: CailynAsset?

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
        alertKind: ActionAlertKind = .none,
        alertIdentifier: String? = nil,
        alertScheduledAt: Date? = nil,
        person: CailynPerson? = nil,
        asset: CailynAsset? = nil,
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
        self.alertKindRaw = alertKind.rawValue
        self.alertIdentifier = alertIdentifier
        self.alertScheduledAt = alertScheduledAt
        self.person = person
        self.asset = asset
    }

    var alertKind: ActionAlertKind {
        get { ActionAlertKind(rawValue: alertKindRaw ?? "") ?? .none }
        set { alertKindRaw = newValue.rawValue }
    }

    func complete(at date: Date = .now) {
        status = .complete
        completedAt = date
        modifiedAt = date
    }

    func markWaiting(on person: CailynPerson?, followUpAt: Date?, date: Date = .now) {
        self.person = person
        self.followUpAt = followUpAt
        waitingSince = date
        status = .waiting
        modifiedAt = date
    }
}

enum ActionAlertKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case reminder
    case prominentAlarm

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "No Alert"
        case .reminder: "Reminder"
        case .prominentAlarm: "Prominent Alarm"
        }
    }
}

enum CalendarEventSource: String, Codable, CaseIterable {
    case cailyn
    case appleCalendar
    case microsoftGraph

    var label: String {
        switch self {
        case .cailyn: "CAILYN"
        case .appleCalendar: "APPLE CALENDAR"
        case .microsoftGraph: "MICROSOFT 365"
        }
    }
}

@Model
final class CailynCalendarEvent {
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
    var shiftRaw: String?

    var source: CalendarEventSource {
        get { CalendarEventSource(rawValue: sourceRaw) ?? .cailyn }
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
        source: CalendarEventSource = .cailyn,
        externalID: String? = nil,
        location: String? = nil,
        notes: String = "",
        shift: WorkShift? = nil
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
        self.shiftRaw = (shift ?? ShiftSchedule.stored.shift(containing: startAt))?.rawValue
    }
}

@Model
final class CailynPerson {
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

    @Relationship(deleteRule: .nullify, inverse: \CailynAction.person)
    var actions: [CailynAction]

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
final class CailynAsset {
    var id: UUID
    var name: String
    var category: String
    var area: String
    var statusRaw: String
    var details: String
    var lastChecked: Date?
    var nextCheck: Date?
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \CailynAction.asset)
    var actions: [CailynAction]

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
final class CailynLogEntry {
    var id: UUID
    var timestamp: Date
    var text: String
    var kindRaw: String
    var actionID: UUID?
    var personID: UUID?
    var assetID: UUID?
    var shiftRaw: String?

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
        assetID: UUID? = nil,
        shift: WorkShift? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.kindRaw = kind.rawValue
        self.actionID = actionID
        self.personID = personID
        self.assetID = assetID
        self.shiftRaw = (shift ?? ShiftSchedule.stored.shift(containing: timestamp))?.rawValue
    }
}

@Model
final class CailynRoutine {
    var id: UUID
    var title: String
    var scheduleDescription: String
    var nextDue: Date?
    var lastCompleted: Date?
    var isEnabled: Bool
    var shiftRaw: String?

    @Relationship(deleteRule: .cascade, inverse: \CailynRoutineItem.routine)
    var items: [CailynRoutineItem]

    init(
        id: UUID = UUID(),
        title: String,
        scheduleDescription: String,
        nextDue: Date? = nil,
        lastCompleted: Date? = nil,
        isEnabled: Bool = true,
        shift: WorkShift? = nil,
        items: [CailynRoutineItem] = []
    ) {
        self.id = id
        self.title = title
        self.scheduleDescription = scheduleDescription
        self.nextDue = nextDue
        self.lastCompleted = lastCompleted
        self.isEnabled = isEnabled
        self.shiftRaw = shift?.rawValue
        self.items = items
    }
}

@Model
final class CailynRoutineItem {
    var id: UUID
    var title: String
    var sortOrder: Int
    var completedAt: Date?
    var routine: CailynRoutine?

    init(id: UUID = UUID(), title: String, sortOrder: Int, completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.sortOrder = sortOrder
        self.completedAt = completedAt
    }
}

enum ReminderUrgency: Int, Codable, CaseIterable, Identifiable, Sendable {
    case routine = 0
    case normal = 1
    case high = 2
    case critical = 3

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .routine: "Routine"
        case .normal: "Normal"
        case .high: "High"
        case .critical: "Critical"
        }
    }
}

@Model
final class CailynReminder {
    var id: UUID
    var title: String
    var notes: String
    var dueAt: Date
    var urgencyRaw: Int
    var alertKindRaw: String
    var alertIdentifier: String?
    var alertScheduledAt: Date?
    var routineID: UUID?
    var isComplete: Bool
    var createdAt: Date

    var urgency: ReminderUrgency {
        get { ReminderUrgency(rawValue: urgencyRaw) ?? .normal }
        set { urgencyRaw = newValue.rawValue }
    }

    var alertKind: ActionAlertKind {
        get { ActionAlertKind(rawValue: alertKindRaw) ?? .none }
        set { alertKindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueAt: Date,
        urgency: ReminderUrgency = .normal,
        alertKind: ActionAlertKind = .none,
        alertIdentifier: String? = nil,
        alertScheduledAt: Date? = nil,
        routineID: UUID? = nil,
        isComplete: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.urgencyRaw = urgency.rawValue
        self.alertKindRaw = alertKind.rawValue
        self.alertIdentifier = alertIdentifier
        self.alertScheduledAt = alertScheduledAt
        self.routineID = routineID
        self.isComplete = isComplete
        self.createdAt = createdAt
    }
}

@Model
final class CailynTurnoverNote {
    var id: UUID
    var title: String
    var capturedAt: Date
    var approvedAt: Date
    var sourceRaw: String
    var rawTranscript: String
    var shiftRaw: String?
    var overview: String
    var unitStatus: String
    var events: String
    var abnormalConditions: String
    var completedWork: String
    var openActions: String
    var waitingOn: String
    var upcomingWork: String
    var safetyNotes: String
    var uncertainties: String

    init(
        id: UUID = UUID(),
        title: String,
        capturedAt: Date = .now,
        approvedAt: Date = .now,
        shift: WorkShift? = nil,
        source: CaptureInputSource,
        rawTranscript: String,
        overview: String,
        unitStatus: String,
        events: String,
        abnormalConditions: String,
        completedWork: String,
        openActions: String,
        waitingOn: String,
        upcomingWork: String,
        safetyNotes: String,
        uncertainties: String
    ) {
        self.id = id
        self.title = title
        self.capturedAt = capturedAt
        self.approvedAt = approvedAt
        self.shiftRaw = (shift ?? ShiftSchedule.stored.shift(containing: capturedAt))?.rawValue
        self.sourceRaw = source.rawValue
        self.rawTranscript = rawTranscript
        self.overview = overview
        self.unitStatus = unitStatus
        self.events = events
        self.abnormalConditions = abnormalConditions
        self.completedWork = completedWork
        self.openActions = openActions
        self.waitingOn = waitingOn
        self.upcomingWork = upcomingWork
        self.safetyNotes = safetyNotes
        self.uncertainties = uncertainties
    }

    var source: CaptureInputSource {
        get { CaptureInputSource(rawValue: sourceRaw) ?? .typed }
        set { sourceRaw = newValue.rawValue }
    }
}

enum CaptureInputSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case typed
    case voice

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

@Model
final class CailynTemplate {
    var id: UUID
    var title: String
    var category: String
    var instructions: String
    var fieldLines: String
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        category: String = "General",
        instructions: String = "",
        fields: [String] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.instructions = instructions
        self.fieldLines = fields.joined(separator: "\n")
        self.createdAt = createdAt
        self.modifiedAt = createdAt
    }

    var fields: [String] {
        get { fieldLines.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        set { fieldLines = newValue.joined(separator: "\n") }
    }
}

@Model
final class CailynKnowledgeItem {
    var id: UUID
    var title: String
    var body: String
    var source: String
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        source: String = "Cailyn Note",
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.source = source
        self.createdAt = createdAt
        self.modifiedAt = createdAt
    }

    var shareText: String {
        "\(title)\n\n\(body)\n\nSource: \(source)"
    }
}

@Model
final class CailynKnowledgeDocument {
    var id: UUID
    var title: String
    var fileName: String
    var folderID: UUID?
    var importedAt: Date
    var pageCount: Int
    var chunkCount: Int
    var contentHash: String

    init(
        id: UUID = UUID(),
        title: String,
        fileName: String,
        folderID: UUID? = nil,
        importedAt: Date = .now,
        pageCount: Int,
        chunkCount: Int,
        contentHash: String
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.folderID = folderID
        self.importedAt = importedAt
        self.pageCount = pageCount
        self.chunkCount = chunkCount
        self.contentHash = contentHash
    }
}

@Model
final class CailynKnowledgeFolder {
    var id: UUID
    var name: String
    var parentID: UUID?
    var modifiedAt: Date

    init(id: UUID = UUID(), name: String, parentID: UUID? = nil, modifiedAt: Date = .now) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.modifiedAt = modifiedAt
    }
}

@Model
final class CailynKnowledgeChunk {
    var id: UUID
    var documentID: UUID
    var pageNumber: Int
    var chunkNumber: Int
    var content: String
    var searchTerms: String
    var embeddingData: Data?

    init(
        id: UUID = UUID(),
        documentID: UUID,
        pageNumber: Int,
        chunkNumber: Int,
        content: String,
        searchTerms: String,
        embeddingData: Data? = nil
    ) {
        self.id = id
        self.documentID = documentID
        self.pageNumber = pageNumber
        self.chunkNumber = chunkNumber
        self.content = content
        self.searchTerms = searchTerms
        self.embeddingData = embeddingData
    }
}
