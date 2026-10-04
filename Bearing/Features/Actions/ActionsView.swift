import SwiftData
import SwiftUI

struct ActionsView: View {
    @Query private var actions: [BearingAction]
    @State private var status: ActionStatus?

    private var filtered: [BearingAction] {
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

                List(filtered) { action in
                    NavigationLink { ActionDetailView(action: action) } label: { ActionListRow(action: action) }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(BearingTheme.line)
                }
                .scrollContentBackground(.hidden)
                .overlay {
                    if filtered.isEmpty { ContentUnavailableView("No Actions", systemImage: "checkmark.circle", description: Text("Nothing is in this state.")) }
                }
            }
        }
        .navigationTitle("ACTIONS")
    }
}

private struct ActionListRow: View {
    let action: BearingAction
    var body: some View {
        HStack(spacing: 13) {
            Text(action.priority.code)
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(action.priority == .immediate ? BearingTheme.urgent : BearingTheme.olive)
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
    @Bindable var action: BearingAction

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
                            action.complete()
                            context.insert(BearingLogEntry(text: "Completed: \(action.title)", kind: .action, actionID: action.id))
                            try? context.save()
                        } label: { Label("Complete Action", systemImage: "checkmark.circle.fill") }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(action.asset?.name ?? action.priority.code)
        .navigationBarTitleDisplayMode(.inline)
    }
}
