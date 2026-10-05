import SwiftData
import SwiftUI

struct RoutinesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CailynRoutine.title) private var routines: [CailynRoutine]
    @State private var showsNewRoutine = false
    @State private var selection = Set<UUID>()
    @State private var pendingDeletion = Set<UUID>()
    @State private var confirmsDeletion = false
    @State private var selectedShift = "all"
    @State private var errorMessage: String?

    private var filteredRoutines: [CailynRoutine] {
        guard selectedShift != "all" else { return routines }
        return routines.filter { $0.shiftRaw == nil || $0.shiftRaw == selectedShift }
    }

    var body: some View {
        ZStack {
            PaperBackground()
            if filteredRoutines.isEmpty {
                ContentUnavailableView {
                    Label(selectedShift == "all" ? "No Routines" : "No \(selectedShift.capitalized) Shift Routines", systemImage: "checklist")
                } description: {
                    Text("Create a checklist for each shift, or add a ready-to-use starter routine.")
                } actions: {
                    Button("Add \(selectedShift == "night" ? "Night" : "Day") Shift Starter") {
                        addStarter(selectedShift == "night" ? .night : .day)
                    }.buttonStyle(.borderedProminent)
                }
            } else {
                List(selection: $selection) {
                    Section {
                        Picker("Shift", selection: $selectedShift) {
                            Text("All").tag("all")
                            ForEach(WorkShift.allCases) { Text($0.title.replacingOccurrences(of: " Shift", with: "")).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                    }
                    ForEach(filteredRoutines) { routine in
                    NavigationLink { RoutineDetailView(routine: routine) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(routine.title).font(.headline)
                                if let shift = routine.shiftRaw.flatMap(WorkShift.init(rawValue:)) {
                                    OperationalBadge(text: shift.title, tone: .normal)
                                } else {
                                    OperationalBadge(text: "Every Shift", tone: .neutral)
                                }
                                if !routine.isEnabled { Text("PAUSED").font(.caption2.bold()).foregroundStyle(.secondary) }
                            }
                            Text(routine.scheduleDescription).font(.subheadline).foregroundStyle(.secondary)
                            if let nextDue = routine.nextDue {
                                Text("Next: \(nextDue.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(CailynTheme.champagne)
                            }
                        }
                        .padding(.vertical, 7)
                    }
                    .tag(routine.id)
                    .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("ROUTINES")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !selection.isEmpty {
                    Button(role: .destructive) {
                        pendingDeletion = selection
                        confirmsDeletion = true
                    } label: { Label("Delete Selected", systemImage: "trash") }
                }
                EditButton()
                Menu {
                    Button("New Routine") { showsNewRoutine = true }
                    Button("Day Shift Starter") { addStarter(.day) }
                    Button("Night Shift Starter") { addStarter(.night) }
                } label: { Label("New Routine", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showsNewRoutine) { NewRoutineView() }
        .alert("Routine Could Not Be Saved", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .confirmationDialog("Delete \(pendingDeletion.count) routine\(pendingDeletion.count == 1 ? "" : "s")?", isPresented: $confirmsDeletion) {
            Button("Delete", role: .destructive, action: deletePending)
            Button("Cancel", role: .cancel) { pendingDeletion.removeAll() }
        } message: { Text("This also removes the checklist items inside the selected routines.") }
    }

    private func deletePending() {
        do {
            routines.filter { pendingDeletion.contains($0.id) }.forEach(context.delete)
            try context.save()
            selection.subtract(pendingDeletion)
            pendingDeletion.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addStarter(_ shift: WorkShift) {
        let items = shift.routineDefaults.enumerated().map {
            CailynRoutineItem(title: $0.element, sortOrder: $0.offset)
        }
        context.insert(CailynRoutine(
            title: "\(shift.title) Start of Shift",
            scheduleDescription: "At the start of each \(shift.rawValue) shift",
            nextDue: .now,
            shift: shift,
            items: items
        ))
        do {
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NewRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var schedule = "Daily"
    @State private var nextDue = Date.now
    @State private var itemLines = ""
    @State private var shiftAssignment = "all"
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    TextField("Name", text: $title)
                    TextField("Schedule description", text: $schedule)
                    Picker("Work Shift", selection: $shiftAssignment) {
                        Text("Every Shift").tag("all")
                        ForEach(WorkShift.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    DatePicker("Next due", selection: $nextDue)
                }
                Section {
                    TextEditor(text: $itemLines).frame(minHeight: 200)
                } header: { Text("Checklist") } footer: { Text("Enter one checklist item per line.") }
            }
            .navigationTitle("New Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .alert("Routine Could Not Be Created", isPresented: Binding(
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
        let items = itemLines.split(whereSeparator: \.isNewline).enumerated().map {
            CailynRoutineItem(title: String($0.element), sortOrder: $0.offset)
        }
        context.insert(CailynRoutine(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            scheduleDescription: schedule,
            nextDue: nextDue,
            shift: WorkShift(rawValue: shiftAssignment),
            items: items
        ))
        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RoutineDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var routine: CailynRoutine
    @State private var newItemTitle = ""
    @State private var errorMessage: String?

    private var sortedItems: [CailynRoutineItem] { routine.items.sorted { $0.sortOrder < $1.sortOrder } }

    var body: some View {
        Form {
            Section("Routine") {
                TextField("Name", text: $routine.title)
                TextField("Schedule", text: $routine.scheduleDescription)
                Picker("Work Shift", selection: Binding(
                    get: { routine.shiftRaw ?? "all" },
                    set: { routine.shiftRaw = $0 == "all" ? nil : $0 }
                )) {
                    Text("Every Shift").tag("all")
                    ForEach(WorkShift.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Enabled", isOn: $routine.isEnabled)
                DatePicker("Next due", selection: Binding(
                    get: { routine.nextDue ?? .now },
                    set: { routine.nextDue = $0 }
                ))
            }
            Section {
                ForEach(sortedItems) { item in
                    HStack(spacing: 10) {
                        Button {
                            item.completedAt = item.completedAt == nil ? .now : nil
                            saveChanges()
                        } label: {
                            Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill")
                                .foregroundStyle(item.completedAt == nil ? .secondary : CailynTheme.champagne)
                        }
                        .buttonStyle(.plain)
                        TextField("Checklist item", text: Binding(
                            get: { item.title },
                            set: { item.title = $0 }
                        ))
                    }
                }
                .onDelete(perform: deleteItems)
                .onMove(perform: moveItems)
                HStack {
                    TextField("Add checklist item", text: $newItemTitle)
                        .onSubmit(addItem)
                    Button(action: addItem) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .disabled(newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add checklist item")
                }
            } header: {
                Text("Checklist")
            }
            Section {
                Button("Reset Checklist") {
                    routine.items.forEach { $0.completedAt = nil }
                    saveChanges()
                }
                Button("Complete Routine") {
                    routine.items.forEach { $0.completedAt = .now }
                    routine.lastCompleted = .now
                    saveChanges()
                }
                .disabled(routine.items.isEmpty)
            }
        }
        .navigationTitle(routine.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .alert("Routine Could Not Be Saved", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onDisappear(perform: saveChanges)
    }

    private func addItem() {
        let title = newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let item = CailynRoutineItem(title: title, sortOrder: sortedItems.count)
        item.routine = routine
        routine.items.append(item)
        newItemTitle = ""
        saveChanges()
    }

    private func deleteItems(at offsets: IndexSet) {
        let itemsToDelete = offsets.map { sortedItems[$0] }
        routine.items.removeAll { item in itemsToDelete.contains(where: { $0.id == item.id }) }
        itemsToDelete.forEach(context.delete)
        normalizeSortOrder()
        saveChanges()
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var items = sortedItems
        items.move(fromOffsets: source, toOffset: destination)
        routine.items = items
        normalizeSortOrder(items)
        saveChanges()
    }

    private func normalizeSortOrder(_ orderedItems: [CailynRoutineItem]? = nil) {
        let items = orderedItems ?? routine.items.sorted { $0.sortOrder < $1.sortOrder }
        for (index, item) in items.enumerated() {
            item.sortOrder = index
        }
    }

    private func saveChanges() {
        do {
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
