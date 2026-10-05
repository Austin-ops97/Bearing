import SwiftData
import SwiftUI

struct KnowledgeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CailynKnowledgeItem.modifiedAt, order: .reverse) private var items: [CailynKnowledgeItem]
    @State private var showsNewItem = false
    @State private var selection = Set<UUID>()
    @State private var pendingDeletion = Set<UUID>()
    @State private var confirmsDeletion = false

    var body: some View {
        ZStack {
            PaperBackground()
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No Knowledge Yet", systemImage: "books.vertical")
                } description: {
                    Text("Add approved references and notes you want Cailyn to preserve.")
                } actions: {
                    Button("Add Knowledge") { showsNewItem = true }.buttonStyle(.borderedProminent)
                }
            } else {
                List(items, selection: $selection) { item in
                    NavigationLink { KnowledgeDetailView(item: item) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.headline)
                            Text(item.body).lineLimit(2).font(.subheadline).foregroundStyle(.secondary)
                            Text(item.source.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(CailynTheme.champagne)
                        }
                        .padding(.vertical, 7)
                    }
                    .tag(item.id)
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("KNOWLEDGE")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !selection.isEmpty {
                    Button(role: .destructive) {
                        pendingDeletion = selection
                        confirmsDeletion = true
                    } label: { Label("Delete Selected", systemImage: "trash") }
                }
                EditButton()
                Button { showsNewItem = true } label: { Label("Add Knowledge", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showsNewItem) { NewKnowledgeView() }
        .confirmationDialog("Delete \(pendingDeletion.count) knowledge item\(pendingDeletion.count == 1 ? "" : "s")?", isPresented: $confirmsDeletion) {
            Button("Delete", role: .destructive, action: deletePending)
            Button("Cancel", role: .cancel) { pendingDeletion.removeAll() }
        }
    }

    private func deletePending() {
        items.filter { pendingDeletion.contains($0.id) }.forEach(context.delete)
        try? context.save()
        selection.subtract(pendingDeletion)
        pendingDeletion.removeAll()
    }
}

private struct NewKnowledgeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var bodyText = ""
    @State private var source = "Cailyn Note"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Source or reference", text: $source)
                TextEditor(text: $bodyText).frame(minHeight: 260)
            }
            .navigationTitle("Add Knowledge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }

    private func save() {
        context.insert(CailynKnowledgeItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines), body: bodyText, source: source))
        try? context.save()
        dismiss()
    }
}

struct KnowledgeDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var item: CailynKnowledgeItem

    var body: some View {
        Form {
            Section("Reference") {
                TextField("Title", text: $item.title)
                TextField("Source", text: $item.source)
            }
            Section("Content") { TextEditor(text: $item.body).frame(minHeight: 260) }
            Section {
                ShareLink(item: item.shareText) {
                    Label("Add to Apple Notes or Share", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Apple does not provide apps direct write access to Notes. The share sheet is the supported Apple workflow; choose Notes to create a copy there.")
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            item.modifiedAt = .now
            try? context.save()
        }
    }
}
