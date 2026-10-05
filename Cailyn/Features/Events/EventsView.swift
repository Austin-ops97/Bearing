import SwiftData
import SwiftUI

struct EventsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CailynCalendarEvent.startAt) private var events: [CailynCalendarEvent]
    @State private var selectedShift: String = "all"
    @State private var editingEvent: CailynCalendarEvent?
    @State private var isAddingEvent = false
    @State private var pendingDeletion: CailynCalendarEvent?
    @State private var errorMessage: String?

    private var filteredEvents: [CailynCalendarEvent] {
        guard selectedShift != "all" else { return events }
        return events.filter { $0.shiftRaw == selectedShift }
    }

    var body: some View {
        ZStack {
            PaperBackground()
            if filteredEvents.isEmpty {
                ContentUnavailableView {
                    Label(selectedShift == "all" ? "No Events" : "No \(selectedShift.capitalized) Shift Events", systemImage: "calendar")
                } description: {
                    Text("Add upcoming events and assign them to the shift they belong to.")
                } actions: {
                    Button("Add Event") { isAddingEvent = true }.buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    Section {
                        Picker("Shift", selection: $selectedShift) {
                            Text("All Shifts").tag("all")
                            ForEach(WorkShift.allCases) { shift in Text(shift.title).tag(shift.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                    }
                    ForEach(filteredEvents) { event in
                        Button { editingEvent = event } label: { EventRow(event: event) }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .contextMenu {
                                Button("Edit Event", systemImage: "pencil") { editingEvent = event }
                                Button("Delete Event", systemImage: "trash", role: .destructive) { pendingDeletion = event }
                            }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("EVENTS")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAddingEvent = true } label: { Label("Add Event", systemImage: "plus") }
                    .accessibilityIdentifier("events.add")
            }
        }
        .sheet(isPresented: $isAddingEvent) { EventEditorView(suggestedDate: .now) }
        .sheet(item: $editingEvent) { event in EventEditorView(event: event, suggestedDate: event.startAt) }
        .confirmationDialog(
            "Delete \(pendingDeletion?.title ?? "event")?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let event = pendingDeletion else { return }
                Task { await delete(event) }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("The event will be removed from Cailyn and, if linked, from Apple Calendar.")
        }
        .alert("Event Could Not Be Changed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    @MainActor
    private func delete(_ event: CailynCalendarEvent) async {
        do {
            if let externalID = event.externalID {
                try await AppleCalendarService.shared.deleteEvent(identifier: externalID)
            }
            context.delete(event)
            try context.save()
            pendingDeletion = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EventRow: View {
    let event: CailynCalendarEvent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.startAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .foregroundStyle(CailynTheme.champagne)
                Text(event.endAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 68, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(event.title).font(.headline).foregroundStyle(.primary)
                Text(event.startAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
                if let shift = event.shiftRaw.flatMap(WorkShift.init(rawValue:)) {
                    OperationalBadge(text: ShiftSchedule.stored.label(for: shift), tone: .normal)
                }
                if !event.location.orEmpty.isEmpty {
                    Label(event.location.orEmpty, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if event.externalID != nil {
                Image(systemName: "calendar.badge.checkmark").foregroundStyle(CailynTheme.champagneGlow)
                    .accessibilityLabel("Also in Apple Calendar")
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct EventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @StateObject private var localModel = CailynLocalModelManager.shared
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var location: String
    @State private var notes: String
    @State private var preparationMinutes: Int
    @State private var transitionMinutes: Int
    @State private var assignment: ShiftAssignment
    @State private var syncWithCalendar: Bool
    @State private var aiDescription = ""
    @State private var isDrafting = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let event: CailynCalendarEvent?

    init(event: CailynCalendarEvent? = nil, suggestedDate: Date) {
        self.event = event
        let start = event?.startAt ?? Self.defaultStart(on: suggestedDate)
        _title = State(initialValue: event?.title ?? "")
        _start = State(initialValue: start)
        _end = State(initialValue: event?.endAt ?? start.addingTimeInterval(60 * 60))
        _location = State(initialValue: event?.location ?? "")
        _notes = State(initialValue: event?.notes ?? "")
        _preparationMinutes = State(initialValue: event?.preparationMinutes ?? 0)
        _transitionMinutes = State(initialValue: event?.transitionMinutes ?? 0)
        _assignment = State(initialValue: event?.shiftRaw.flatMap(WorkShift.init(rawValue:)).map(Self.assignment(for:)) ?? .automatic)
        _syncWithCalendar = State(initialValue: event?.externalID != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)
                    DatePicker("Starts", selection: $start)
                    DatePicker("Ends", selection: $end, in: start...)
                    Picker("Work Shift", selection: $assignment) {
                        Text("Automatic · \(automaticShiftLabel)").tag(ShiftAssignment.automatic)
                        Text(ShiftSchedule.stored.label(for: .day)).tag(ShiftAssignment.day)
                        Text(ShiftSchedule.stored.label(for: .night)).tag(ShiftAssignment.night)
                    }
                    TextField("Location", text: $location)
                    Stepper("Preparation · \(preparationMinutes)m", value: $preparationMinutes, in: 0...240, step: 5)
                    Stepper("Transition · \(transitionMinutes)m", value: $transitionMinutes, in: 0...240, step: 5)
                }
                Section("Draft with On-Device AI") {
                    TextField("Describe the event", text: $aiDescription, axis: .vertical)
                        .lineLimit(2...5)
                    Button {
                        Task { await draftEvent() }
                    } label: {
                        Label(isDrafting ? "Drafting…" : "Draft Title & Notes", systemImage: "sparkles")
                    }
                    .disabled(!localModel.isLoaded || isDrafting || aiDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !localModel.isLoaded {
                        Text("Download the optional on-device model in Settings to enable AI drafting.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Notes") { TextEditor(text: $notes).frame(minHeight: 100) }
                Section("Apple Calendar") {
                    Toggle("Also add to Apple Calendar", isOn: $syncWithCalendar)
                    Text("Cailyn always saves the event locally. Calendar access is only requested if you enable this option.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(event == nil ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(event == nil ? "Add" : "Save") { Task { await save() } }
                        .disabled(isSaving || isDrafting || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end <= start)
                }
            }
            .alert("Event Could Not Be Saved", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var automaticShiftLabel: String {
        ShiftSchedule.stored.shift(containing: start).map(ShiftSchedule.stored.label(for:)) ?? "Off shift"
    }

    @MainActor
    private func draftEvent() async {
        isDrafting = true
        defer { isDrafting = false }
        do {
            let prompt = try CailynModelPrompts.eventDraft(text: aiDescription)
            let response = try await localModel.complete(prompt: prompt)
            let draft = try LocalEventDraft.decode(response)
            guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LocalEventDraftError.missingTitle
            }
            title = draft.title
            location = draft.location ?? ""
            notes = draft.notes
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let shift = assignment.shift ?? ShiftSchedule.stored.shift(containing: start)
        do {
            var externalID = event?.externalID
            if syncWithCalendar {
                externalID = try await AppleCalendarService.shared.saveEvent(
                    identifier: externalID,
                    title: cleanTitle,
                    start: start,
                    end: end,
                    location: location.isEmpty ? nil : location,
                    notes: notes
                )
            } else if let linkedID = externalID {
                try await AppleCalendarService.shared.deleteEvent(identifier: linkedID)
                externalID = nil
            }

            if let event {
                event.title = cleanTitle
                event.startAt = start
                event.endAt = end
                event.location = location.isEmpty ? nil : location
                event.notes = notes
                event.preparationMinutes = preparationMinutes
                event.transitionMinutes = transitionMinutes
                event.shiftRaw = shift?.rawValue
                event.externalID = externalID
                event.source = externalID == nil ? .cailyn : .appleCalendar
            } else {
                context.insert(CailynCalendarEvent(
                    title: cleanTitle,
                    startAt: start,
                    endAt: end,
                    preparationMinutes: preparationMinutes,
                    transitionMinutes: transitionMinutes,
                    source: externalID == nil ? .cailyn : .appleCalendar,
                    externalID: externalID,
                    location: location.isEmpty ? nil : location,
                    notes: notes,
                    shift: shift
                ))
            }
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    private static func assignment(for shift: WorkShift) -> ShiftAssignment {
        shift == .day ? .day : .night
    }

    private static func defaultStart(on date: Date) -> Date {
        let shift = ShiftSchedule.stored.shift(containing: date) ?? .day
        guard let interval = ShiftSchedule.stored.interval(for: shift, containing: date) else { return date }
        return interval.start.addingTimeInterval(60 * 60)
    }
}

private struct LocalEventDraft: Decodable {
    let title: String
    let location: String?
    let notes: String

    static func decode(_ response: String) throws -> Self {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end else { throw LocalEventDraftError.invalidResponse }
        return try JSONDecoder().decode(Self.self, from: Data(trimmed[start...end].utf8))
    }
}

private enum LocalEventDraftError: LocalizedError {
    case invalidResponse
    case missingTitle

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The local model did not return a valid event draft. Your existing fields were not changed."
        case .missingTitle: "The local model did not suggest an event title. Your existing fields were not changed."
        }
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
