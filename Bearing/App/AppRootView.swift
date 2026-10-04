import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case sitrep = "SITREP"
    case plan = "PLAN"
    case actions = "ACTIONS"
    case templates = "TEMPLATES"
    case people = "PEOPLE"
    case knowledge = "KNOWLEDGE"
    case assistant = "ASSISTANT"
    case ops = "OPS"
    case log = "LOG"
    case settings = "SETTINGS"
    case more = "MORE"

    var id: Self { self }

    var icon: String {
        switch self {
        case .sitrep: "scope"
        case .plan: "calendar"
        case .actions: "checkmark.circle"
        case .templates: "rectangle.3.group"
        case .ops: "square.3.layers.3d"
        case .people: "person.2"
        case .knowledge: "books.vertical"
        case .assistant: "sparkles"
        case .log: "book.closed"
        case .settings: "gearshape"
        case .more: "ellipsis"
        }
    }
}

struct AppRootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: AppSection = .sitrep
    @State private var showsCapture = false
    @State private var showsSearch = false

    var body: some View {
        Group {
            if sizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .background(BearingTheme.paper)
        .sheet(isPresented: $showsCapture) { CaptureView() }
        .sheet(isPresented: $showsSearch) { BearingSearchView() }
    }

    private var iPhoneLayout: some View {
        TabView(selection: $selection) {
            ForEach([AppSection.sitrep, .plan, .actions, .templates, .more]) { section in
                NavigationStack { destination(for: section) }
                    .tag(section)
                    .tabItem { Label(section.rawValue.capitalized, systemImage: section.icon) }
            }
        }
        .safeAreaInset(edge: .bottom, alignment: .trailing) {
            CaptureButton { showsCapture = true }
                .padding(.trailing, 18)
                .padding(.bottom, 58)
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                BearingWordmark()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)

                List(AppSection.allCases.filter { $0 != .more }) { section in
                    Button {
                        selection = section
                    } label: {
                        Label(section.rawValue, systemImage: section.icon)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selection == section ? Color.white.opacity(0.12) : Color.clear)
                    .accessibilityIdentifier("navigation.\(section.rawValue.lowercased())")
                }
                .scrollContentBackground(.hidden)

                Spacer()

                Button { showsSearch = true } label: {
                    Label("SEARCH", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(20)
            }
            .foregroundStyle(.white.opacity(0.92))
            .background(BearingTheme.charcoal)
            .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 270)
        } detail: {
            NavigationStack { destination(for: selection) }
                .overlay(alignment: .bottomTrailing) {
                    CaptureButton { showsCapture = true }.padding(28)
                }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func destination(for section: AppSection) -> some View {
        switch section {
        case .sitrep: SitrepView(onSearch: { showsSearch = true })
        case .plan: PlanView()
        case .actions: ActionsView()
        case .templates: FoundationSurfaceView(kind: .templates)
        case .ops: OpsView()
        case .people: PeopleView()
        case .knowledge: FoundationSurfaceView(kind: .knowledge)
        case .assistant: FoundationSurfaceView(kind: .assistant)
        case .log: LogView()
        case .settings: SettingsView()
        case .more: MoreView()
        }
    }
}

private struct MoreView: View {
    var body: some View {
        ZStack {
            PaperBackground()
            List {
                Section("Bearing") {
                    NavigationLink { PeopleView() } label: { Label("People", systemImage: "person.2") }
                    NavigationLink { FoundationSurfaceView(kind: .knowledge) } label: { Label("Knowledge", systemImage: "books.vertical") }
                    NavigationLink { FoundationSurfaceView(kind: .assistant) } label: { Label("Assistant", systemImage: "sparkles") }
                }
                Section("Operations") {
                    NavigationLink { OpsView() } label: { Label("Assets", systemImage: "square.3.layers.3d") }
                    NavigationLink { LogView() } label: { Label("Log", systemImage: "book.closed") }
                }
                Section {
                    NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("MORE")
    }
}

enum FoundationSurfaceKind {
    case templates, knowledge, assistant

    var title: String {
        switch self {
        case .templates: "TEMPLATES"
        case .knowledge: "KNOWLEDGE"
        case .assistant: "ASSISTANT"
        }
    }

    var icon: String {
        switch self {
        case .templates: "rectangle.3.group"
        case .knowledge: "books.vertical"
        case .assistant: "sparkles"
        }
    }

    var message: String {
        switch self {
        case .templates: "Reusable forms, checklists, and playbooks will live here. Nothing is created until you define or approve it."
        case .knowledge: "Approved documents and source-grounded references will live here. Bearing will always preserve provenance."
        case .assistant: "Advanced assistance is not connected. Core planning and capture continue to work locally without cloud AI."
        }
    }
}

struct FoundationSurfaceView: View {
    let kind: FoundationSurfaceKind
    var body: some View {
        ZStack {
            PaperBackground()
            ContentUnavailableView(kind.title.capitalized, systemImage: kind.icon, description: Text(kind.message))
                .frame(maxWidth: 520)
        }
        .navigationTitle(kind.title)
    }
}

private struct BearingWordmark: View {
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "location.north.fill")
                .font(.title3)
                .foregroundStyle(BearingTheme.amber)
            Text("BEARING")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .tracking(2.2)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bearing")
    }
}

private struct CaptureButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("CAPTURE", systemImage: "plus")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .tracking(1)
                .padding(.horizontal, 18)
                .frame(height: 48)
                .background(BearingTheme.olive, in: Capsule())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("capture.open")
    }
}
