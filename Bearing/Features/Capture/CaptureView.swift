import SwiftData
import SwiftUI

struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \BearingPerson.displayName) private var people: [BearingPerson]
    @Query(sort: \BearingAsset.name) private var assets: [BearingAsset]
    @State private var text = ""
    @State private var proposal: CaptureProposal?
    @State private var isProcessing = false
    @FocusState private var isFocused: Bool
    private let intelligence: any IntelligenceService = LocalRuleIntelligenceService()

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CAPTURE")
                                .font(.system(.caption, design: .rounded, weight: .bold)).tracking(2).foregroundStyle(BearingTheme.olive)
                            Text("Get it out of your head.")
                                .font(.system(.title, design: .serif, weight: .semibold))
                        }

                        TextField("Check with Mike Wednesday about Yankee 3…", text: $text, axis: .vertical)
                            .font(.title3)
                            .lineLimit(4...10)
                            .padding(18)
                            .background(BearingTheme.paperRaised, in: RoundedRectangle(cornerRadius: 14))
                            .overlay { RoundedRectangle(cornerRadius: 14).stroke(BearingTheme.olive.opacity(0.4), lineWidth: 1) }
                            .focused($isFocused)
                            .accessibilityIdentifier("capture.text")

                        if let proposal {
                            ProposalReview(proposal: proposal)
                        } else {
                            Label("Bearing reviews its interpretation before anything is committed.", systemImage: "checkmark.shield")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("New Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if let proposal {
                        Button("Save") { save(proposal) }.fontWeight(.semibold).accessibilityIdentifier("capture.save")
                    } else {
                        Button("Review") { review() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                            .accessibilityIdentifier("capture.review")
                    }
                }
            }
            .onAppear { isFocused = true }
            .onChange(of: text) { _, _ in proposal = nil }
        }
        .presentationDetents([.large])
    }

    private func review() {
        isProcessing = true
        Task {
            proposal = await intelligence.proposeAction(from: text, people: people.map(\.displayName), assets: assets.map(\.name), now: .now)
            isProcessing = false
        }
    }

    private func save(_ proposal: CaptureProposal) {
        let person = people.first { $0.displayName == proposal.personName }
        let asset = assets.first { $0.name == proposal.assetName }
        let action = BearingAction(
            title: proposal.title,
            details: proposal.originalText,
            priority: proposal.priority,
            status: proposal.status,
            dueAt: proposal.dueAt,
            followUpAt: proposal.status == .waiting ? proposal.dueAt : nil,
            waitingSince: proposal.status == .waiting ? .now : nil,
            source: "Capture",
            person: person,
            asset: asset
        )
        context.insert(action)
        context.insert(BearingLogEntry(text: "Captured action: \(action.title)", kind: .action, actionID: action.id))
        try? context.save()
        dismiss()
    }
}

private struct ProposalReview: View {
    let proposal: CaptureProposal
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "REVIEW INTERPRETATION", trailing: proposal.confidence < 0.75 ? "CHECK DETAILS" : nil)
            ReviewLine(label: "ACTION", value: proposal.title)
            if let person = proposal.personName { ReviewLine(label: "PERSON", value: person) }
            if let asset = proposal.assetName { ReviewLine(label: "ASSET", value: asset) }
            if let date = proposal.dueAt { ReviewLine(label: "DATE", value: date.formatted(date: .abbreviated, time: .omitted)) }
            ReviewLine(label: "PRIORITY", value: "\(proposal.priority.code) — \(proposal.priority.label)")
            ReviewLine(label: "STATUS", value: proposal.status.label)
        }
        .bearingSurface()
    }
}

private struct ReviewLine: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary).frame(width: 65, alignment: .leading)
            Text(value).font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(BearingTheme.line).frame(height: 0.5) }
    }
}

