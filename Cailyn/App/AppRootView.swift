import SwiftData
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "OVERVIEW"
    case plan = "PLAN"
    case events = "EVENTS"
    case routines = "ROUTINES"
    case reminders = "REMINDERS"
    case alarms = "ALARMS"
    case actions = "ACTIONS"
    case templates = "TEMPLATES"
    case people = "PEOPLE"
    case knowledge = "KNOWLEDGE"
    case assistant = "ASSISTANT"
    case ops = "OPS"
    case turnovers = "TURNOVERS"
    case log = "LOG"
    case settings = "SETTINGS"
    case more = "MORE"

    var id: Self { self }

    var icon: String {
        switch self {
        case .overview: "circle.hexagongrid.fill"
        case .plan: "calendar"
        case .events: "calendar.badge.clock"
        case .routines: "checklist"
        case .reminders: "bell"
        case .alarms: "alarm"
        case .actions: "checkmark.circle"
        case .templates: "rectangle.3.group"
        case .ops: "square.3.layers.3d"
        case .turnovers: "arrow.left.arrow.right"
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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("appearance.mode") private var appearanceMode = AppAppearance.dark.rawValue
    @AppStorage(PersonalizationKey.completedOnboarding) private var didCompleteSetup = false
    @AppStorage("migration.removeLegacyDemoData") private var didRemoveLegacyDemoData = false
    @State private var selection: AppSection = .overview
    @State private var navigationRoots = Dictionary(
        uniqueKeysWithValues: AppSection.allCases.map { ($0, UUID()) }
    )
    @State private var showsCapture = false
    @State private var showsSearch = false
    @State private var captureMode: CaptureMode = .action
    @State private var startsCaptureInVoice = false
    @State private var migrationError: String?

    var body: some View {
        Group {
            if sizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .background(CailynTheme.paper)
        .sheet(isPresented: $showsCapture) {
            CaptureView(initialMode: captureMode, startsVoiceCapture: startsCaptureInVoice)
        }
        .sheet(isPresented: $showsSearch) { CailynSearchView() }
        .fullScreenCover(isPresented: Binding(
            get: { !didCompleteSetup },
            set: { _ in }
        )) {
            InitialSetupView()
                .interactiveDismissDisabled()
        }
        .task {
            removeLegacyDemoDataIfNeeded()
        }
        .alert("App Setup", isPresented: Binding(
            get: { migrationError != nil },
            set: { if !$0 { migrationError = nil } }
        )) {
            Button("Retry Cleanup") { removeLegacyDemoDataIfNeeded() }
            Button("OK", role: .cancel) { migrationError = nil }
        } message: {
            Text(migrationError ?? "Unknown error")
        }
        .preferredColorScheme(AppAppearance(rawValue: appearanceMode)?.colorScheme)
    }

    private var iPhoneLayout: some View {
        TabView(selection: tabSelection) {
            ForEach([AppSection.overview, .plan, .events, .routines, .more]) { section in
                NavigationStack { destination(for: section) }
                    .id(navigationRoots[section])
                    .tag(section)
                    .tabItem { Label(section.rawValue.capitalized, systemImage: section.icon) }
            }
        }
        .safeAreaInset(edge: .bottom, alignment: .trailing) {
            captureButton
                .padding(.trailing, 18)
                .padding(.bottom, 58)
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                    Button { selectRoot(.overview) } label: {
                        CailynWordmark()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("navigation.overview.logo")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)

                List(AppSection.allCases.filter { $0 != .more }) { section in
                    Button {
                        selectRoot(section)
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
            .background(CailynTheme.charcoal)
            .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 270)
        } detail: {
            NavigationStack { destination(for: selection) }
                .id(navigationRoots[selection])
                .overlay(alignment: .bottomTrailing) {
                    captureButton.padding(28)
                }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var captureButton: some View {
        CaptureButton(
            action: { openCapture(mode: .action, startsInVoice: false) },
            voiceAction: { openCapture(mode: .action, startsInVoice: true) },
            turnoverAction: { openCapture(mode: .turnover, startsInVoice: true) }
        )
    }

    private func openCapture(mode: CaptureMode, startsInVoice: Bool) {
        captureMode = mode
        startsCaptureInVoice = startsInVoice
        showsCapture = true
    }

    private func removeLegacyDemoDataIfNeeded() {
        guard !didRemoveLegacyDemoData else { return }
        do {
            try LegacyDemoDataCleanup.removeLegacySamples(in: modelContext)
            didRemoveLegacyDemoData = true
            migrationError = nil
        } catch {
            migrationError = "Cailyn could not remove the old sample records: \(error.localizedDescription)"
        }
    }

    private var tabSelection: Binding<AppSection> {
        Binding(
            get: { selection },
            set: { selectRoot($0) }
        )
    }

    private func selectRoot(_ section: AppSection) {
        selection = section
        for root in AppSection.allCases {
            navigationRoots[root] = UUID()
        }
    }

    @ViewBuilder
    private func destination(for section: AppSection) -> some View {
        switch section {
        case .overview:
            SitrepView(
                onSearch: { showsSearch = true },
                onOverview: { selectRoot(.overview) }
            )
        case .plan: PlanView()
        case .events: EventsView()
        case .routines: RoutinesView()
        case .reminders: RemindersView()
        case .alarms: RemindersView(showsAlarmsOnly: true)
        case .actions: ActionsView()
        case .templates: TemplatesView()
        case .ops: OpsView()
        case .turnovers: TurnoverView()
        case .people: PeopleView()
        case .knowledge: KnowledgeView()
        case .assistant: CailynAssistantView()
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
                Section("Cailyn") {
                    NavigationLink { ActionsView() } label: { Label("Actions", systemImage: "checkmark.circle") }
                    NavigationLink { RemindersView() } label: { Label("Reminders", systemImage: "bell") }
                    NavigationLink { RemindersView(showsAlarmsOnly: true) } label: { Label("Alarms", systemImage: "alarm") }
                    NavigationLink { PeopleView() } label: { Label("People", systemImage: "person.2") }
                    NavigationLink { KnowledgeView() } label: { Label("Knowledge", systemImage: "books.vertical") }
                    NavigationLink { CailynAssistantView() } label: { Label("Assistant", systemImage: "sparkles") }
                    NavigationLink { ExperimentalBotView() } label: { Label("Experimental Bot Lab", systemImage: "testtube.2") }
                    NavigationLink { Microsoft365View() } label: { Label("Outlook & Teams", systemImage: "envelope.badge") }
                }
                Section("Operations") {
                    NavigationLink { TemplatesView() } label: { Label("Templates", systemImage: "rectangle.3.group") }
                    NavigationLink { TurnoverView() } label: { Label("Shift Turnovers", systemImage: "arrow.left.arrow.right") }
                    NavigationLink { ShiftScheduleView() } label: { Label("Work Shifts", systemImage: "clock.badge") }
                    NavigationLink { OpsView() } label: { Label("Assets", systemImage: "square.3.layers.3d") }
                    NavigationLink { LogView() } label: { Label("Log", systemImage: "book.closed") }
                }
                Section {
                    NavigationLink { InitialSetupView(isEditing: true) } label: { Label("Personalize Cailyn", systemImage: "person.crop.circle") }
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
        case .knowledge: "Approved documents and source-grounded references will live here. Cailyn will always preserve provenance."
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

private struct CailynWordmark: View {
    var body: some View {
        HStack(spacing: 11) {
            Image("CailynMark")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("CAILYN")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .tracking(2.2)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cailyn")
    }
}

private struct CaptureButton: View {
    let action: () -> Void
    let voiceAction: () -> Void
    let turnoverAction: () -> Void

    var body: some View {
        Button(action: action) {
            Label("CAPTURE", systemImage: "plus")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .tracking(1)
                .padding(.horizontal, 18)
                .frame(height: 48)
                .background(CailynTheme.champagne, in: Capsule())
                .foregroundStyle(CailynTheme.charcoal)
                .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("capture.open")
        .contextMenu {
            Button(action: voiceAction) {
                Label("Voice", systemImage: "waveform")
            }
            Button(action: turnoverAction) {
                Label("Shift Turnover", systemImage: "arrow.left.arrow.right")
            }
        }
    }
}
