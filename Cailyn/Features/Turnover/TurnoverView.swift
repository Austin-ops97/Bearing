import SwiftData
import SwiftUI

struct TurnoverView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CailynTurnoverNote.approvedAt, order: .reverse) private var notes: [CailynTurnoverNote]
    @State private var selection = Set<UUID>()
    @State private var pendingDeletion = Set<UUID>()
    @State private var showsDeleteConfirmation = false
    @State private var showsNewTurnover = false

    var body: some View {
        ZStack {
            PaperBackground()
            if notes.isEmpty {
                ContentUnavailableView(
                    "No Shift Turnovers",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Choose Shift Turnover in Capture. Cailyn will organize the transcript and wait for your approval before saving it.")
                )
            } else {
                List(notes, selection: $selection) { note in
                    NavigationLink { TurnoverDetailView(note: note) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.title).font(.headline)
                            HStack {
                                Text(note.approvedAt.formatted(date: .abbreviated, time: .shortened))
                                Text("·")
                                Label(note.source.label, systemImage: note.source == .voice ? "waveform" : "keyboard")
                                if let shift = note.shiftRaw.flatMap(WorkShift.init(rawValue:)) {
                                    Text("· \(shift.title.uppercased())")
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            if !note.overview.isEmpty { Text(note.overview).font(.subheadline).lineLimit(2).foregroundStyle(.secondary) }
                        }
                        .padding(.vertical, 7)
                    }
                    .tag(note.id)
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("TURNOVERS")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !selection.isEmpty {
                    Button(role: .destructive) {
                        pendingDeletion = selection
                        showsDeleteConfirmation = true
                    } label: { Label("Delete Selected", systemImage: "trash") }
                }
                EditButton()
                Button { showsNewTurnover = true } label: { Label("New Turnover", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showsNewTurnover) { CaptureView(initialMode: .turnover) }
        .confirmationDialog(
            "Delete \(pendingDeletion.count) turnover\(pendingDeletion.count == 1 ? "" : "s")?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deletePending)
            Button("Cancel", role: .cancel) { pendingDeletion.removeAll() }
        } message: {
            Text("This permanently removes the selected notes and their source transcripts.")
        }
    }

    private func deletePending() {
        notes.filter { pendingDeletion.contains($0.id) }.forEach(context.delete)
        try? context.save()
        selection.subtract(pendingDeletion)
        pendingDeletion.removeAll()
    }
}

struct TurnoverDetailView: View {
    let note: CailynTurnoverNote

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(note.title).font(.system(.title2, design: .serif, weight: .semibold))
                        Text("Approved \(note.approvedAt.formatted(date: .abbreviated, time: .shortened)) · \(note.source.label)")
                            .font(.caption).foregroundStyle(.secondary)
                        if let shift = note.shiftRaw.flatMap(WorkShift.init(rawValue:)) {
                            OperationalBadge(text: ShiftSchedule.stored.label(for: shift), tone: .normal)
                        }
                    }
                    TurnoverSectionView(title: "OVERVIEW", value: note.overview)
                    TurnoverSectionView(title: "UNIT / ASSET STATUS", value: note.unitStatus)
                    TurnoverSectionView(title: "EVENTS", value: note.events)
                    TurnoverSectionView(title: "ABNORMAL CONDITIONS", value: note.abnormalConditions)
                    TurnoverSectionView(title: "WORK COMPLETED", value: note.completedWork)
                    TurnoverSectionView(title: "OPEN ACTIONS", value: note.openActions)
                    TurnoverSectionView(title: "WAITING ON", value: note.waitingOn)
                    TurnoverSectionView(title: "UPCOMING WORK", value: note.upcomingWork)
                    TurnoverSectionView(title: "SAFETY / OPERATIONAL NOTES", value: note.safetyNotes)
                    TurnoverSectionView(title: "NEEDS CONFIRMATION", value: note.uncertainties)
                    DisclosureGroup("SOURCE TRANSCRIPT") {
                        Text(note.rawTranscript).font(.body).textSelection(.enabled).padding(.top, 12)
                    }
                    .cailynSurface()
                    Label("The source is text only. Cailyn did not retain a recording.", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(22).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Turnover")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TurnoverSectionView: View {
    let title: String
    let value: String
    var body: some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: title)
                Text(value).font(.body).textSelection(.enabled)
            }
            .cailynSurface()
        }
    }
}
