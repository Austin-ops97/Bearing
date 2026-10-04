import SwiftData
import SwiftUI

struct OpsView: View {
    @Query(sort: \BearingAsset.name) private var assets: [BearingAsset]

    private var grouped: [(String, [BearingAsset])] {
        Dictionary(grouping: assets, by: \.area).sorted { $0.key < $1.key }
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    ForEach(grouped, id: \.0) { area, assets in
                        VStack(alignment: .leading, spacing: 0) {
                            SectionHeading(title: area.uppercased(), trailing: "\(assets.count) ASSETS")
                            ForEach(assets) { asset in
                                NavigationLink { AssetDetailView(asset: asset) } label: { AssetRow(asset: asset) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(22).frame(maxWidth: 900).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("OPS")
    }
}

private struct AssetRow: View {
    let asset: BearingAsset
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: asset.status == .normal ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(asset.status == .normal ? BearingTheme.olive : BearingTheme.urgent)
            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name).font(.headline).foregroundStyle(.primary)
                Text(asset.category).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            OperationalBadge(text: asset.status.label, tone: asset.status == .normal ? .normal : .urgent)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(BearingTheme.line).frame(height: 0.5) }
    }
}

private struct AssetDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var asset: BearingAsset

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
                        LabeledContent("Last checked", value: lastChecked.formatted(date: .abbreviated, time: .shortened)).bearingSurface()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeading(title: "OPEN ITEMS", trailing: "\(asset.actions.filter { $0.status != .complete }.count)")
                        ForEach(asset.actions.filter { $0.status != .complete }) { ActionSummaryRow(action: $0) }
                    }
                    Button {
                        asset.lastChecked = .now
                        if asset.status == .unknown { asset.status = .normal }
                        context.insert(BearingLogEntry(text: "\(asset.name) verified \(asset.status.label.lowercased())", kind: .asset, assetID: asset.id))
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

