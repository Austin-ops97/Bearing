import SwiftData
import SwiftUI

struct LogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CailynLogEntry.timestamp, order: .reverse) private var entries: [CailynLogEntry]
    @State private var showsNewEntry = false
    @State private var editingEntry: CailynLogEntry?
    @State private var selection = Set<UUID>()
    @State private var pendingDeletion = Set<UUID>()
    @State private var showsDeleteConfirmation = false

    var body: some View {
        ZStack {
            PaperBackground()
            List(entries, selection: $selection) { entry in
                Button { editingEntry = entry } label: {
                    HStack(alignment: .top, spacing: 18) {
                        Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .foregroundStyle(CailynTheme.champagne).frame(width: 58, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.text).font(.body).foregroundStyle(.primary)
                            HStack {
                                Text(entry.kind.rawValue.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                                if let shift = entry.shiftRaw.flatMap(WorkShift.init(rawValue:)) {
                                    Text("· \(shift.title.uppercased())")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(CailynTheme.champagne)
                                }
                            }
                        }
                    }
                    .tag(entry.id)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("LOG")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !selection.isEmpty {
                    Button(role: .destructive) {
                        pendingDeletion = selection
                        showsDeleteConfirmation = true
                    } label: { Label("Delete Selected", systemImage: "trash") }
                }
                EditButton()
                Button { showsNewEntry = true } label: { Label("Log Entry", systemImage: "square.and.pencil") }
            }
        }
        .sheet(isPresented: $showsNewEntry) { LogEntryEditorView() }
        .sheet(item: $editingEntry) { entry in LogEntryEditorView(entry: entry) }
        .confirmationDialog(
            "Delete \(pendingDeletion.count) log entr\(pendingDeletion.count == 1 ? "y" : "ies")?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deletePending)
            Button("Cancel", role: .cancel) { pendingDeletion.removeAll() }
        } message: {
            Text("Deleted log entries cannot be restored.")
        }
    }

    private struct LogEntryEditorView: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.modelContext) private var context
        @StateObject private var localModel = CailynLocalModelManager.shared
        @State private var text: String
        @State private var timestamp: Date
        @State private var assignment: ShiftAssignment
        @State private var isOrganizing = false
        @State private var clarificationFlags: [String] = []
        @State private var errorMessage: String?
        private let entry: CailynLogEntry?

        init(entry: CailynLogEntry? = nil) {
            self.entry = entry
            let timestamp = entry?.timestamp ?? .now
            _text = State(initialValue: entry?.text ?? "")
            _timestamp = State(initialValue: timestamp)
            _assignment = State(initialValue: entry?.shiftRaw.flatMap(WorkShift.init(rawValue:)).map { $0 == .day ? .day : .night } ?? .automatic)
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section("Log Entry") {
                        TextField("What happened?", text: $text, axis: .vertical).lineLimit(3...8)
                        DatePicker("Time", selection: $timestamp)
                        Picker("Work Shift", selection: $assignment) {
                            Text("Automatic · \(automaticShiftLabel)").tag(ShiftAssignment.automatic)
                            Text(ShiftSchedule.stored.label(for: .day)).tag(ShiftAssignment.day)
                            Text(ShiftSchedule.stored.label(for: .night)).tag(ShiftAssignment.night)
                        }
                    }
                    Section("Organize with On-Device AI") {
                        Button {
                            Task { await organizeNote() }
                        } label: {
                            Label(isOrganizing ? "Organizing…" : "Polish Log Note", systemImage: "sparkles")
                        }
                        .disabled(!localModel.isLoaded || isOrganizing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if !localModel.isLoaded {
                            Text("Download the optional on-device model in Settings to enable note organization.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(clarificationFlags, id: \.self) {
                            Label($0, systemImage: "questionmark.circle").font(.footnote)
                        }
                    }
                }
                .navigationTitle(entry == nil ? "New Log Entry" : "Edit Log Entry")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(entry == nil ? "Add" : "Save", action: save)
                            .disabled(isOrganizing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .alert("Log Entry Could Not Be Saved", isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "Unknown error")
                }
            }
        }

        private var automaticShiftLabel: String {
            ShiftSchedule.stored.shift(containing: timestamp).map(ShiftSchedule.stored.label(for:)) ?? "Off shift"
        }

        @MainActor
        private func organizeNote() async {
            isOrganizing = true
            defer { isOrganizing = false }
            do {
                let prompt = try CailynModelPrompts.logOrganization(text: text)
                let response = try await localModel.complete(prompt: prompt)
                let draft = try LocalLogDraft.decode(response)
                guard HybridIntelligenceService.isSafeNormalization(draft.text, of: text) else {
                    throw LocalLogDraftError.unsafeRewrite
                }
                text = draft.text
                clarificationFlags = Array(draft.clarificationFlags.prefix(3))
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        private func save() {
            let shift = assignment.shift ?? ShiftSchedule.stored.shift(containing: timestamp)
            do {
                if let entry {
                    entry.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    entry.timestamp = timestamp
                    entry.shiftRaw = shift?.rawValue
                } else {
                    context.insert(CailynLogEntry(
                        timestamp: timestamp,
                        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                        shift: shift
                    ))
                }
                try context.save()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deletePending() {
        entries.filter { pendingDeletion.contains($0.id) }.forEach(context.delete)
        try? context.save()
        selection.subtract(pendingDeletion)
        pendingDeletion.removeAll()
    }

    private struct LocalLogDraft: Decodable {
        let text: String
        let clarificationFlags: [String]

        static func decode(_ response: String) throws -> Self {
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let start = trimmed.firstIndex(of: "{"),
                  let end = trimmed.lastIndex(of: "}"),
                  start <= end else { throw LocalLogDraftError.invalidResponse }
            return try JSONDecoder().decode(Self.self, from: Data(trimmed[start...end].utf8))
        }
    }

    private enum LocalLogDraftError: LocalizedError {
        case invalidResponse
        case unsafeRewrite

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "The local model did not return a valid log draft. Your existing note was not changed."
            case .unsafeRewrite: "The local model changed protected details, so the original note was kept."
            }
        }
    }
}
