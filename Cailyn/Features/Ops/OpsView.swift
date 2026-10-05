import SwiftData
import SwiftUI

struct OpsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CailynAsset.name) private var assets: [CailynAsset]
    @State private var selection = Set<UUID>()
    @State private var pendingDeletion = Set<UUID>()
    @State private var showsDeleteConfirmation = false
    @State private var showsNewAsset = false

    private var grouped: [(String, [CailynAsset])] {
        Dictionary(grouping: assets, by: \.area).sorted { $0.key < $1.key }
    }

    var body: some View {
        ZStack {
            PaperBackground()
            if assets.isEmpty {
                ContentUnavailableView {
                    Label("No Assets", systemImage: "square.3.layers.3d")
                } description: {
                    Text("Add equipment, locations, or systems you need to track.")
                } actions: {
                    Button("Add Asset") { showsNewAsset = true }.buttonStyle(.borderedProminent)
                }
            } else { List(selection: $selection) {
                ForEach(grouped, id: \.0) { area, assets in
                    Section {
                        ForEach(assets) { asset in
                            NavigationLink { AssetDetailView(asset: asset) } label: { AssetRow(asset: asset) }
                                .tag(asset.id)
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        HStack {
                            Text(area.uppercased())
                            Spacer()
                            Text("\(assets.count) ASSETS")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("OPS")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !selection.isEmpty {
                    Button(role: .destructive) {
                        pendingDeletion = selection
                        showsDeleteConfirmation = true
                    } label: { Label("Delete Selected", systemImage: "trash") }
                }
                EditButton()
                Button { showsNewAsset = true } label: { Label("Add Asset", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showsNewAsset) { NewAssetView() }
        .confirmationDialog(
            "Delete \(pendingDeletion.count) asset\(pendingDeletion.count == 1 ? "" : "s")?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deletePending)
            Button("Cancel", role: .cancel) { pendingDeletion.removeAll() }
        } message: {
            Text("Their actions remain in Cailyn, but will no longer be linked to these assets.")
        }
    }

    private func deletePending() {
        assets.filter { pendingDeletion.contains($0.id) }.forEach(context.delete)
        try? context.save()
        selection.subtract(pendingDeletion)
        pendingDeletion.removeAll()
    }
}

private struct NewAssetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var category = "Equipment"
    @State private var area = "Operations"
    @State private var status = AssetStatus.normal
    @State private var details = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Asset") {
                    TextField("Name", text: $name)
                    TextField("Category", text: $category)
                    TextField("Area", text: $area)
                    Picker("Status", selection: $status) {
                        ForEach(AssetStatus.allCases, id: \.rawValue) { Text($0.label.capitalized).tag($0) }
                    }
                }
                Section("Details") { TextEditor(text: $details).frame(minHeight: 140) }
            }
            .navigationTitle("Add Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }

    private func save() {
        context.insert(CailynAsset(name: name.trimmingCharacters(in: .whitespacesAndNewlines), category: category, area: area, status: status, details: details))
        try? context.save()
        dismiss()
    }
}

private struct AssetRow: View {
    let asset: CailynAsset
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: asset.status == .normal ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(asset.status == .normal ? CailynTheme.champagne : CailynTheme.urgent)
            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name).font(.headline).foregroundStyle(.primary)
                Text(asset.category).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            OperationalBadge(text: asset.status.label, tone: asset.status == .normal ? .normal : .urgent)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(CailynTheme.line).frame(height: 0.5) }
    }
}

struct AssetDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var asset: CailynAsset

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(asset.name).font(.system(.largeTitle, design: .serif, weight: .semibold))
                            Text(asset.category.uppercased()).font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.secondary)
                        }
                        Spacer()
                        OperationalBadge(text: asset.status.label, tone: asset.status == .normal ? .normal : .urgent)
                    }
                    if let lastChecked = asset.lastChecked {
                        LabeledContent("Last checked", value: lastChecked.formatted(date: .abbreviated, time: .shortened)).cailynSurface()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeading(title: "OPEN ITEMS", trailing: "\(asset.actions.filter { $0.status != .complete }.count)")
                        ForEach(asset.actions.filter { $0.status != .complete }) { ActionSummaryRow(action: $0) }
                    }
                    Button {
                        asset.lastChecked = .now
                        if asset.status == .unknown { asset.status = .normal }
                        context.insert(CailynLogEntry(text: "\(asset.name) verified \(asset.status.label.lowercased())", kind: .asset, assetID: asset.id))
                        try? context.save()
                    } label: {
                        Label("Record Check", systemImage: "checkmark.seal").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(22).frame(maxWidth: 780).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("ASSET")
        .navigationBarTitleDisplayMode(.inline)
    }
}
