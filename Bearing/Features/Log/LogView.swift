import SwiftData
import SwiftUI

struct LogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BearingLogEntry.timestamp, order: .reverse) private var entries: [BearingLogEntry]
    @State private var showsEntry = false
    @State private var entryText = ""

    var body: some View {
        ZStack {
            PaperBackground()
            List(entries) { entry in
                HStack(alignment: .top, spacing: 18) {
                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundStyle(BearingTheme.olive).frame(width: 58, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.text).font(.body)
                        Text(entry.kind.rawValue.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8).listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("LOG")
        .toolbar {
            Button { showsEntry = true } label: { Label("Log Entry", systemImage: "square.and.pencil") }
        }
        .alert("New Log Entry", isPresented: $showsEntry) {
            TextField("What happened?", text: $entryText)
            Button("Cancel", role: .cancel) { entryText = "" }
            Button("Add") {
                let clean = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return }
                context.insert(BearingLogEntry(text: clean))
                try? context.save()
                entryText = ""
            }
        }
    }
}
