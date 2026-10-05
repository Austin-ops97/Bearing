import SwiftData
import SwiftUI

struct CailynSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var actions: [CailynAction]
    @Query private var people: [CailynPerson]
    @Query private var assets: [CailynAsset]
    @Query private var logs: [CailynLogEntry]
    @Query private var events: [CailynCalendarEvent]
    @Query private var turnovers: [CailynTurnoverNote]
    @Query private var templates: [CailynTemplate]
    @Query private var knowledgeItems: [CailynKnowledgeItem]
    @Query private var knowledgeDocuments: [CailynKnowledgeDocument]
    @Query private var knowledgeChunks: [CailynKnowledgeChunk]
    @State private var query = ""
    @FocusState private var focused: Bool

    private var normalized: String { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var matchingActions: [CailynAction] { actions.filter { $0.title.lowercased().contains(normalized) || $0.details.lowercased().contains(normalized) || $0.asset?.name.lowercased().contains(normalized) == true || $0.person?.displayName.lowercased().contains(normalized) == true } }
    private var matchingPeople: [CailynPerson] { people.filter { $0.displayName.lowercased().contains(normalized) || $0.organization?.lowercased().contains(normalized) == true } }
    private var matchingAssets: [CailynAsset] { assets.filter { $0.name.lowercased().contains(normalized) || $0.details.lowercased().contains(normalized) } }
    private var matchingLogs: [CailynLogEntry] { logs.filter { $0.text.lowercased().contains(normalized) } }
    private var matchingEvents: [CailynCalendarEvent] { events.filter { $0.title.lowercased().contains(normalized) || $0.notes.lowercased().contains(normalized) } }
    private var matchingTurnovers: [CailynTurnoverNote] { turnovers.filter { $0.title.lowercased().contains(normalized) || $0.rawTranscript.lowercased().contains(normalized) || $0.overview.lowercased().contains(normalized) || $0.openActions.lowercased().contains(normalized) } }
    private var matchingTemplates: [CailynTemplate] { templates.filter { $0.title.lowercased().contains(normalized) || $0.category.lowercased().contains(normalized) || $0.instructions.lowercased().contains(normalized) || $0.fieldLines.lowercased().contains(normalized) } }
    private var matchingKnowledge: [CailynKnowledgeItem] { knowledgeItems.filter { $0.title.lowercased().contains(normalized) || $0.body.lowercased().contains(normalized) || $0.source.lowercased().contains(normalized) } }
    private var matchingKnowledgeDocuments: [CailynKnowledgeDocument] {
        let matchingIDs = Set(knowledgeChunks.filter { $0.content.lowercased().contains(normalized) }.map(\.documentID))
        return knowledgeDocuments.filter {
            $0.title.lowercased().contains(normalized)
                || $0.fileName.lowercased().contains(normalized)
                || matchingIDs.contains($0.id)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                if normalized.isEmpty {
                    ContentUnavailableView("Search Cailyn", systemImage: "magnifyingglass", description: Text("Find actions, people, assets, events, turnovers, templates, and knowledge."))
                } else {
                    List {
                        if !matchingActions.isEmpty { Section("Actions") { ForEach(matchingActions) { action in NavigationLink { ActionDetailView(action: action) } label: { Label(action.title, systemImage: "checkmark.circle") } } } }
                        if !matchingPeople.isEmpty { Section("People") { ForEach(matchingPeople) { person in NavigationLink { PersonDetailView(person: person) } label: { Label(person.displayName, systemImage: "person") } } } }
                        if !matchingAssets.isEmpty { Section("Assets") { ForEach(matchingAssets) { asset in NavigationLink { AssetDetailView(asset: asset) } label: { Label(asset.name, systemImage: "square.3.layers.3d") } } } }
                        if !matchingLogs.isEmpty { Section("Log") { ForEach(matchingLogs) { Label($0.text, systemImage: "book.closed") } } }
                        if !matchingEvents.isEmpty { Section("Calendar") { ForEach(matchingEvents) { event in Label("\(event.title) · \(event.startAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar") } } }
                        if !matchingTurnovers.isEmpty { Section("Shift Turnovers") { ForEach(matchingTurnovers) { note in NavigationLink { TurnoverDetailView(note: note) } label: { Label(note.title, systemImage: "arrow.left.arrow.right") } } } }
                        if !matchingTemplates.isEmpty { Section("Templates") { ForEach(matchingTemplates) { template in NavigationLink { TemplateDetailView(template: template) } label: { Label(template.title, systemImage: "rectangle.3.group") } } } }
                        if !matchingKnowledge.isEmpty { Section("Knowledge") { ForEach(matchingKnowledge) { item in NavigationLink { KnowledgeDetailView(item: item) } label: { Label(item.title, systemImage: "books.vertical") } } } }
                        if !matchingKnowledgeDocuments.isEmpty { Section("Knowledge Documents") { ForEach(matchingKnowledgeDocuments) { document in NavigationLink { KnowledgeDocumentDetailView(document: document) } label: { Label(document.title, systemImage: "doc.text") } } } }
                    }
                    .scrollContentBackground(.hidden)
                    .overlay { if matchingActions.isEmpty && matchingPeople.isEmpty && matchingAssets.isEmpty && matchingLogs.isEmpty && matchingEvents.isEmpty && matchingTurnovers.isEmpty && matchingTemplates.isEmpty && matchingKnowledge.isEmpty && matchingKnowledgeDocuments.isEmpty { ContentUnavailableView.search(text: query) } }
                }
            }
            .navigationTitle("SEARCH")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Yankee charger")
            .searchFocused($focused)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear { focused = true }
        }
    }
}
