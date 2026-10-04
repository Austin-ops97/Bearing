import SwiftData
import SwiftUI

struct BearingSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var actions: [BearingAction]
    @Query private var people: [BearingPerson]
    @Query private var assets: [BearingAsset]
    @Query private var logs: [BearingLogEntry]
    @Query private var events: [BearingCalendarEvent]
    @State private var query = ""
    @FocusState private var focused: Bool

    private var normalized: String { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var matchingActions: [BearingAction] { actions.filter { $0.title.lowercased().contains(normalized) || $0.details.lowercased().contains(normalized) || $0.asset?.name.lowercased().contains(normalized) == true || $0.person?.displayName.lowercased().contains(normalized) == true } }
    private var matchingPeople: [BearingPerson] { people.filter { $0.displayName.lowercased().contains(normalized) || $0.organization?.lowercased().contains(normalized) == true } }
    private var matchingAssets: [BearingAsset] { assets.filter { $0.name.lowercased().contains(normalized) || $0.details.lowercased().contains(normalized) } }
    private var matchingLogs: [BearingLogEntry] { logs.filter { $0.text.lowercased().contains(normalized) } }
    private var matchingEvents: [BearingCalendarEvent] { events.filter { $0.title.lowercased().contains(normalized) || $0.notes.lowercased().contains(normalized) } }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                if normalized.isEmpty {
                    ContentUnavailableView("Search Bearing", systemImage: "magnifyingglass", description: Text("Find actions, people, assets, and log entries."))
                } else {
                    List {
                        if !matchingActions.isEmpty { Section("Actions") { ForEach(matchingActions) { action in NavigationLink { ActionDetailView(action: action) } label: { Label(action.title, systemImage: "checkmark.circle") } } } }
                        if !matchingPeople.isEmpty { Section("People") { ForEach(matchingPeople) { Label($0.displayName, systemImage: "person") } } }
                        if !matchingAssets.isEmpty { Section("Assets") { ForEach(matchingAssets) { Label($0.name, systemImage: "square.3.layers.3d") } } }
                        if !matchingLogs.isEmpty { Section("Log") { ForEach(matchingLogs) { Label($0.text, systemImage: "book.closed") } } }
                        if !matchingEvents.isEmpty { Section("Calendar") { ForEach(matchingEvents) { event in Label("\(event.title) · \(event.startAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar") } } }
                    }
                    .scrollContentBackground(.hidden)
                    .overlay { if matchingActions.isEmpty && matchingPeople.isEmpty && matchingAssets.isEmpty && matchingLogs.isEmpty && matchingEvents.isEmpty { ContentUnavailableView.search(text: query) } }
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
