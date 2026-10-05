import SwiftData
import SwiftUI

struct RemindersView: View {
    @Environment(\.modelContext) private var context
    @Query private var reminders: [CailynReminder]
    @Query private var actions: [CailynAction]
    @Query private var routines: [CailynRoutine]
    @State private var showsNewReminder = false
    @State private var errorMessage: String?

    let showsAlarmsOnly: Bool

    init(showsAlarmsOnly: Bool = false) {
        self.showsAlarmsOnly = showsAlarmsOnly
    }

    private var entries: [ReminderListEntry] {
        ReminderListEntry.active(reminders: reminders, actions: actions, routines: routines)
            .filter { !showsAlarmsOnly || $0.alertKind == .prominentAlarm }
            .sorted(by: ReminderListEntry.precedes)
    }

    var body: some View {
        ZStack {
            PaperBackground()
            if entries.isEmpty {
                ContentUnavailableView(
                    showsAlarmsOnly ? "No Alarms" : "No Reminders",
                    systemImage: showsAlarmsOnly ? "alarm" : "bell",
                    description: Text(showsAlarmsOnly
                        ? "Prominent alarms you schedule in Cailyn will appear here."
                        : "Add a reminder with a date, urgency, and optional notification or prominent alarm.")
                )
            } else {
                List(entries) { entry in
                    NavigationLink {
                        switch entry.target {
                        case .reminder(let reminder):
                            ReminderDetailView(reminder: reminder)
                        case .action(let action):
                            ActionDetailView(action: action)
                        }
                    } label: {
                        ReminderEntryRow(entry: entry)
                    }
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if case .reminder(let reminder) = entry.target {
                            Button("Complete", systemImage: "checkmark", action: { complete(reminder) })
                                .tint(CailynTheme.champagne)
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(reminder)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(showsAlarmsOnly ? "ALARMS" : "REMINDERS")
        .toolbar {
            if !showsAlarmsOnly {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsNewReminder = true } label: { Label("New Reminder", systemImage: "plus") }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsNewReminder = true } label: { Label("New Alarm", systemImage: "plus") }
                }
            }
        }
        .sheet(isPresented: $showsNewReminder) {
            ReminderEditorView(startsAsAlarm: showsAlarmsOnly)
        }
        .alert("Reminder Could Not Be Updated", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func complete(_ reminder: CailynReminder) {
        let scheduler = SystemAlertSchedulingService()
        let identifier = reminder.alertIdentifier
        let kind = reminder.alertKind
        reminder.isComplete = true
        do {
            try context.save()
            scheduler.cancel(identifier: identifier, kind: kind)
        } catch {
            reminder.isComplete = false
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ reminder: CailynReminder) {
        let identifier = reminder.alertIdentifier
        let kind = reminder.alertKind
        context.delete(reminder)
        do {
            try context.save()
            SystemAlertSchedulingService().cancel(identifier: identifier, kind: kind)
        } catch {
            context.insert(reminder)
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReminderEntryRow: View {
    let entry: ReminderListEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.alertKind == .prominentAlarm ? "alarm" : "bell")
                .font(.title3)
                .foregroundStyle(entry.urgency.rawValue >= ReminderUrgency.high.rawValue ? CailynTheme.urgent : CailynTheme.champagne)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title).font(.headline)
                Text(entry.dueAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if !entry.notes.isEmpty {
                    Text(entry.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(entry.urgency.label.uppercased())
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(entry.urgency.rawValue >= ReminderUrgency.high.rawValue ? CailynTheme.urgent : .secondary)
                if entry.routineTitle != nil {
                    Label("Routine", systemImage: "checklist")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct ReminderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CailynRoutine.title) private var routines: [CailynRoutine]
    @State private var title: String
    @State private var notes = ""
    @State private var dueAt: Date
    @State private var urgencyRaw = ReminderUrgency.normal.rawValue
    @State private var alertKindRaw = ActionAlertKind.reminder.rawValue
    @State private var routineID: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(routine: CailynRoutine? = nil, startsAsAlarm: Bool = false) {
        _title = State(initialValue: routine?.title ?? "")
        _dueAt = State(initialValue: max(routine?.nextDue ?? .now.addingTimeInterval(3_600), .now.addingTimeInterval(60)))
        _routineID = State(initialValue: routine?.id)
        _alertKindRaw = State(initialValue: startsAsAlarm ? ActionAlertKind.prominentAlarm.rawValue : ActionAlertKind.reminder.rawValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("Title", text: $title)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                    DatePicker("Date and time", selection: $dueAt, in: Date.now...)
                    Picker("Urgency", selection: $urgencyRaw) {
                        ForEach(ReminderUrgency.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Alert", selection: $alertKindRaw) {
                        ForEach(ActionAlertKind.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Linked routine", selection: $routineID) {
                        Text("None").tag(UUID?.none)
                        ForEach(routines) { routine in
                            Text(routine.title).tag(Optional(routine.id))
                        }
                    }
                }
                Section {
                    Label(
                        alertKindRaw == ActionAlertKind.prominentAlarm.rawValue
                            ? "A prominent alarm will be scheduled when available; iOS may fall back to a notification."
                            : "Notifications depend on the permission you grant to Cailyn.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save", action: save)
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Reminder Could Not Be Saved", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        isSaving = true
        Task {
            let scheduler = SystemAlertSchedulingService()
            var receipt: AlertReceipt?
            do {
                receipt = try await scheduler.schedule(
                    title: cleanTitle,
                    notes: notes,
                    at: dueAt,
                    kind: ActionAlertKind(rawValue: alertKindRaw) ?? .none
                )
                let reminder = CailynReminder(
                    title: cleanTitle,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    dueAt: dueAt,
                    urgency: ReminderUrgency(rawValue: urgencyRaw) ?? .normal,
                    alertKind: receipt?.kind ?? .none,
                    alertIdentifier: receipt?.identifier,
                    alertScheduledAt: receipt?.scheduledAt,
                    routineID: routineID
                )
                let linkedRoutine = routines.first(where: { $0.id == routineID })
                let previousDue = linkedRoutine?.nextDue
                linkedRoutine?.nextDue = dueAt
                context.insert(reminder)
                do {
                    try context.save()
                } catch {
                    context.delete(reminder)
                    linkedRoutine?.nextDue = previousDue
                    throw error
                }
                dismiss()
            } catch {
                if let receipt {
                    scheduler.cancel(identifier: receipt.identifier, kind: receipt.kind)
                }
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

struct ReminderDetailView: View {
    @Environment(\.modelContext) private var context
    @Query private var routines: [CailynRoutine]
    @Bindable var reminder: CailynReminder
    @State private var draftTitle: String
    @State private var draftNotes: String
    @State private var draftDueAt: Date
    @State private var draftUrgencyRaw: Int
    @State private var draftAlertKindRaw: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(reminder: CailynReminder) {
        self.reminder = reminder
        _draftTitle = State(initialValue: reminder.title)
        _draftNotes = State(initialValue: reminder.notes)
        _draftDueAt = State(initialValue: reminder.dueAt)
        _draftUrgencyRaw = State(initialValue: reminder.urgencyRaw)
        _draftAlertKindRaw = State(initialValue: reminder.alertKindRaw)
    }

    var body: some View {
        Form {
            Section("Reminder") {
                TextField("Title", text: $draftTitle)
                TextField("Notes", text: $draftNotes, axis: .vertical).lineLimit(2...5)
                DatePicker("Date and time", selection: $draftDueAt)
                Picker("Urgency", selection: $draftUrgencyRaw) {
                    ForEach(ReminderUrgency.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Alert", selection: $draftAlertKindRaw) {
                    ForEach(ActionAlertKind.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            if let routine = routines.first(where: { $0.id == reminder.routineID }) {
                Section("Linked routine") {
                    NavigationLink {
                        RoutineDetailView(routine: routine)
                    } label: {
                        Label(routine.title, systemImage: "checklist")
                    }
                }
            }
            Section {
                Button(isSaving ? "Saving…" : "Save and Update Alert", action: save)
                    .disabled(isSaving || draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Complete Reminder", systemImage: "checkmark.circle", action: complete)
                    .disabled(reminder.isComplete)
            } footer: {
                if let date = reminder.alertScheduledAt {
                    Text("Alert scheduled for \(date.formatted(date: .abbreviated, time: .shortened)).")
                }
            }
        }
        .navigationTitle(reminder.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reminder Could Not Be Updated", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func save() {
        isSaving = true
        Task {
            let scheduler = SystemAlertSchedulingService()
            let previousID = reminder.alertIdentifier
            let previousKind = reminder.alertKind
            let previousScheduledAt = reminder.alertScheduledAt
            let previousTitle = reminder.title
            let previousNotes = reminder.notes
            let previousDueAt = reminder.dueAt
            let previousUrgencyRaw = reminder.urgencyRaw
            let linkedRoutine = routines.first(where: { $0.id == reminder.routineID })
            let previousRoutineDue = linkedRoutine?.nextDue
            var newReceipt: AlertReceipt?
            do {
                newReceipt = try await scheduler.schedule(
                    title: draftTitle,
                    notes: draftNotes,
                    at: draftDueAt,
                    kind: ActionAlertKind(rawValue: draftAlertKindRaw) ?? .none
                )
                reminder.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                reminder.notes = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                reminder.dueAt = draftDueAt
                reminder.urgencyRaw = draftUrgencyRaw
                reminder.alertKind = newReceipt?.kind ?? .none
                reminder.alertIdentifier = newReceipt?.identifier
                reminder.alertScheduledAt = newReceipt?.scheduledAt
                linkedRoutine?.nextDue = draftDueAt
                do {
                    try context.save()
                } catch {
                    reminder.title = previousTitle
                    reminder.notes = previousNotes
                    reminder.dueAt = previousDueAt
                    reminder.urgencyRaw = previousUrgencyRaw
                    reminder.alertIdentifier = previousID
                    reminder.alertKind = previousKind
                    reminder.alertScheduledAt = previousScheduledAt
                    linkedRoutine?.nextDue = previousRoutineDue
                    throw error
                }
                scheduler.cancel(identifier: previousID, kind: previousKind)
                draftTitle = reminder.title
                draftNotes = reminder.notes
                draftAlertKindRaw = reminder.alertKindRaw
            } catch {
                if let newReceipt {
                    scheduler.cancel(identifier: newReceipt.identifier, kind: newReceipt.kind)
                }
                reminder.alertIdentifier = previousID
                reminder.alertKind = previousKind
                reminder.alertScheduledAt = previousScheduledAt
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func complete() {
        let identifier = reminder.alertIdentifier
        let kind = reminder.alertKind
        reminder.isComplete = true
        do {
            try context.save()
            SystemAlertSchedulingService().cancel(identifier: identifier, kind: kind)
        } catch {
            reminder.isComplete = false
            errorMessage = error.localizedDescription
        }
    }
}

struct ReminderListEntry: Identifiable {
    enum Target {
        case reminder(CailynReminder)
        case action(CailynAction)
    }

    let id: UUID
    let title: String
    let notes: String
    let dueAt: Date
    let urgency: ReminderUrgency
    let alertKind: ActionAlertKind
    let routineTitle: String?
    let target: Target

    static func active(
        reminders: [CailynReminder],
        actions: [CailynAction],
        routines: [CailynRoutine]
    ) -> [ReminderListEntry] {
        let reminderRows = reminders.filter { !$0.isComplete }.map { reminder in
            ReminderListEntry(
                id: reminder.id,
                title: reminder.title,
                notes: reminder.notes,
                dueAt: reminder.dueAt,
                urgency: reminder.urgency,
                alertKind: reminder.alertKind,
                routineTitle: routines.first(where: { $0.id == reminder.routineID })?.title,
                target: .reminder(reminder)
            )
        }
        let actionRows = actions.compactMap { action -> ReminderListEntry? in
            guard action.status != .complete, action.alertKind != .none, let dueAt = action.dueAt else { return nil }
            let urgency: ReminderUrgency = switch action.priority {
            case .immediate: .critical
            case .today: .high
            case .planned: .normal
            case .reference: .routine
            }
            return ReminderListEntry(
                id: action.id,
                title: action.title,
                notes: action.details,
                dueAt: dueAt,
                urgency: urgency,
                alertKind: action.alertKind,
                routineTitle: nil,
                target: .action(action)
            )
        }
        return reminderRows + actionRows
    }

    static func precedes(_ lhs: ReminderListEntry, _ rhs: ReminderListEntry) -> Bool {
        if lhs.urgency != rhs.urgency { return lhs.urgency.rawValue > rhs.urgency.rawValue }
        if lhs.dueAt != rhs.dueAt { return lhs.dueAt < rhs.dueAt }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
