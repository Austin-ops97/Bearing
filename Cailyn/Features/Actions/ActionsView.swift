import SwiftData
import SwiftUI

struct ActionsView: View {
    @Environment(\.modelContext) private var context
    @Query private var actions: [CailynAction]
    @State private var status: ActionStatus?
    @State private var selection = Set<UUID>()
    @State private var pendingDeletion = Set<UUID>()
    @State private var showsDeleteConfirmation = false
    @State private var showsNewAction = false
    private let alertScheduler = SystemAlertSchedulingService()

    private var filtered: [CailynAction] {
        actions.filter { action in
            if let status { action.status == status } else { action.status != .complete }
        }.sorted { AttentionEngine.rank($0, $1) }
    }

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 0) {
                Picker("Action status", selection: $status) {
                    Text("CURRENT").tag(ActionStatus?.none)
                    Text("ACTIVE").tag(ActionStatus?.some(.active))
                    Text("WAITING").tag(ActionStatus?.some(.waiting))
                    Text("COMPLETE").tag(ActionStatus?.some(.complete))
                }
                .pickerStyle(.segmented)
                .padding()

                List(filtered, selection: $selection) { action in
                    NavigationLink { ActionDetailView(action: action) } label: { ActionListRow(action: action) }
                        .tag(action.id)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(CailynTheme.line)
                }
                .scrollContentBackground(.hidden)
                .overlay {
                    if filtered.isEmpty { ContentUnavailableView("No Actions", systemImage: "checkmark.circle", description: Text("Nothing is in this state.")) }
                }
            }
        }
        .navigationTitle("ACTIONS")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !selection.isEmpty {
                    Button(role: .destructive) {
                        requestDeletion(selection)
                    } label: {
                        Label("Delete Selected", systemImage: "trash")
                    }
                }
                EditButton()
                Button { showsNewAction = true } label: { Label("New Action", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showsNewAction) { CaptureView(initialMode: .action) }
        .confirmationDialog(
            "Delete \(pendingDeletion.count) action\(pendingDeletion.count == 1 ? "" : "s")?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deletePending)
            Button("Cancel", role: .cancel) { pendingDeletion.removeAll() }
        } message: {
            Text("This removes the selected actions and cancels their pending Cailyn alerts.")
        }
    }

    private func requestDeletion(_ identifiers: Set<UUID>) {
        pendingDeletion = identifiers
        showsDeleteConfirmation = true
    }

    private func deletePending() {
        let doomed = actions.filter { pendingDeletion.contains($0.id) }
        for action in doomed {
            alertScheduler.cancel(identifier: action.alertIdentifier, kind: action.alertKind)
            context.delete(action)
        }
        if !doomed.isEmpty {
            context.insert(CailynLogEntry(text: "Deleted \(doomed.count) action\(doomed.count == 1 ? "" : "s")", kind: .action))
        }
        try? context.save()
        selection.subtract(pendingDeletion)
        pendingDeletion.removeAll()
    }
}

private struct ActionListRow: View {
    let action: CailynAction
    var body: some View {
        HStack(spacing: 13) {
            Text(action.priority.code)
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(action.priority == .immediate ? CailynTheme.urgent : CailynTheme.champagne)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(action.title).font(.headline)
                HStack(spacing: 6) {
                    if let asset = action.asset?.name { Text(asset) }
                    if action.asset != nil, action.person != nil { Text("·") }
                    if let person = action.person?.displayName { Text(person) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            OperationalBadge(text: action.status.label, tone: action.status == .waiting ? .attention : .neutral)
        }
        .padding(.vertical, 7)
        .accessibilityIdentifier("action.\(action.id.uuidString)")
    }
}

struct ActionDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var action: CailynAction
    @State private var alertError: String?
    @State private var isUpdatingAlert = false
    private let alertScheduler = SystemAlertSchedulingService()

    var body: some View {
        ZStack {
            PaperBackground()
            Form {
                Section {
                    TextField("Action", text: $action.title)
                    TextField("Notes", text: $action.details, axis: .vertical).lineLimit(3...8)
                }
                Section("Control") {
                    Picker("Priority", selection: $action.priorityRaw) {
                        ForEach(ActionPriority.allCases) { Text("\($0.code) — \($0.label)").tag($0.rawValue) }
                    }
                    Picker("Status", selection: $action.statusRaw) {
                        ForEach(ActionStatus.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    if let dueAt = action.dueAt { DatePicker("Due", selection: Binding(get: { dueAt }, set: { action.dueAt = $0 })) }
                    Picker("Timing", selection: $action.timingRaw) {
                        ForEach(TimingClassification.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Stepper(
                        "Estimated · \(PlanningEngine.durationText(minutes: action.estimatedDurationMinutes ?? 30))",
                        value: Binding(
                            get: { action.estimatedDurationMinutes ?? 30 },
                            set: { action.estimatedDurationMinutes = $0 }
                        ),
                        in: 5...480,
                        step: 5
                    )
                }
                if action.alertKind != .none {
                    Section {
                        LabeledContent("Type", value: action.alertKind.label)
                        if let scheduledAt = action.alertScheduledAt {
                            LabeledContent("Scheduled", value: scheduledAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        Button {
                            rescheduleAlert()
                        } label: {
                            if isUpdatingAlert {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Label("Update Scheduled Alert", systemImage: "bell.badge")
                            }
                        }
                        .disabled(isUpdatingAlert || action.dueAt == nil || (action.dueAt ?? .distantPast) <= .now)

                        Button("Cancel Alert", role: .destructive, action: cancelAlert)
                    } header: {
                        Text("Alert")
                    } footer: {
                        Text("Use Update Scheduled Alert after changing the title, notes, or due time.")
                    }
                }
                if action.person != nil || action.asset != nil {
                    Section("Related") {
                        if let person = action.person { Label(person.displayName, systemImage: "person") }
                        if let asset = action.asset { Label(asset.name, systemImage: "square.3.layers.3d") }
                    }
                }
                if action.status != .complete {
                    Section {
                        Button {
                            cancelAlert()
                            action.complete()
                            context.insert(CailynLogEntry(text: "Completed: \(action.title)", kind: .action, actionID: action.id))
                            try? context.save()
                        } label: { Label("Complete Action", systemImage: "checkmark.circle.fill") }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(action.asset?.name ?? action.priority.code)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Alert Could Not Be Updated", isPresented: Binding(
            get: { alertError != nil },
            set: { if !$0 { alertError = nil } }
        )) {
            Button("OK", role: .cancel) { alertError = nil }
        } message: {
            Text(alertError ?? "Unknown error")
        }
    }

    private func cancelAlert() {
        alertScheduler.cancel(identifier: action.alertIdentifier, kind: action.alertKind)
        action.alertKind = .none
        action.alertIdentifier = nil
        action.alertScheduledAt = nil
        action.modifiedAt = .now
        try? context.save()
    }

    private func rescheduleAlert() {
        let previousIdentifier = action.alertIdentifier
        let previousKind = action.alertKind
        isUpdatingAlert = true
        Task {
            do {
                let receipt = try await alertScheduler.schedule(
                    title: action.title,
                    notes: action.details,
                    at: action.dueAt,
                    kind: previousKind
                )
                alertScheduler.cancel(identifier: previousIdentifier, kind: previousKind)
                action.alertIdentifier = receipt?.identifier
                action.alertKind = receipt?.kind ?? .none
                action.alertScheduledAt = receipt?.scheduledAt
                action.modifiedAt = .now
                try context.save()
            } catch {
                alertError = error.localizedDescription
            }
            isUpdatingAlert = false
        }
    }
}
