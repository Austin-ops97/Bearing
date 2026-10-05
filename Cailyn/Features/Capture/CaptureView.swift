import SwiftData
import SwiftUI

enum CaptureMode: String, CaseIterable, Identifiable {
    case action = "Quick Action"
    case turnover = "Shift Turnover"
    var id: String { rawValue }
    var icon: String { self == .action ? "bolt.fill" : "arrow.left.arrow.right" }
}

struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CailynPerson.displayName) private var people: [CailynPerson]
    @Query(sort: \CailynAsset.name) private var assets: [CailynAsset]
    @StateObject private var speech = SpeechCaptureController()
    @State private var mode: CaptureMode = .action
    @State private var source: CaptureInputSource = .typed
    @State private var text = ""
    @State private var proposal: CaptureProposal?
    @State private var turnoverDraft: TurnoverDraft?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool
    private let intelligence: any IntelligenceService = HybridIntelligenceService()
    private let alerts: any AlertScheduling = SystemAlertSchedulingService()

    init(initialMode: CaptureMode = .action) {
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        Picker("Capture type", selection: $mode) {
                            ForEach(CaptureMode.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        if proposal == nil && turnoverDraft == nil {
                            inputSurface
                            privacyNote
                            if isProcessing {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Deterministic pass complete. On-device assistance is checking structure; Cailyn validates results locally.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(CailynTheme.paperRaised, in: RoundedRectangle(cornerRadius: 12))
                            }
                        } else if let proposal {
                            ActionProposalEditor(proposal: Binding(get: { proposal }, set: { self.proposal = $0 }))
                        } else if let turnoverDraft {
                            TurnoverDraftEditor(draft: Binding(get: { turnoverDraft }, set: { self.turnoverDraft = $0 }))
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("New Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onChange(of: speech.transcript) { _, value in
                guard source == .voice, !value.isEmpty else { return }
                text = value
            }
            .onChange(of: speech.completedTranscriptGeneration) { _, _ in
                guard source == .voice, !speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                text = speech.transcript
                review(capturedText: speech.transcript)
            }
            .onChange(of: mode) { _, _ in resetInterpretation() }
            .onChange(of: source) { _, newValue in
                if newValue == .typed { speech.cancel(); isFocused = true }
            }
            .onDisappear { speech.cancel() }
            .alert("Capture Needs Attention", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Unknown error") }
        }
        .presentationDetents([.large])
            .interactiveDismissDisabled(speech.isBusy)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAPTURE")
                .font(.system(.caption, design: .rounded, weight: .bold)).tracking(2).foregroundStyle(CailynTheme.champagne)
            Text(mode == .action ? "Get it out of your head." : "Turn the shift into a clear record.")
                .font(.system(.title, design: .serif, weight: .semibold))
            Text(mode == .action
                 ? "Cailyn will interpret the action, time, person, and alert—then wait for your approval."
                 : "Cailyn removes verbal filler, preserves operational facts, and keeps the source transcript for review.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var inputSurface: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Input", selection: $source) {
                Label("Type", systemImage: "keyboard").tag(CaptureInputSource.typed)
                Label("Voice", systemImage: "waveform").tag(CaptureInputSource.voice)
            }
            .pickerStyle(.segmented)

            if source == .voice {
                voiceControls
            }

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: mode == .turnover ? 220 : 130)
                .scrollContentBackground(.hidden)
                .padding(14)
                .background(CailynTheme.paperRaised, in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(source == .voice && speech.isListening ? CailynTheme.champagneGlow : CailynTheme.champagne.opacity(0.4), lineWidth: 1) }
                .focused($isFocused)
                .accessibilityLabel(mode == .action ? "Action capture" : "Shift turnover transcript")
                .accessibilityIdentifier("capture.text")
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(mode == .action
                             ? "Today around 11 o’clock, email JP about the workflow…"
                             : "Describe unit status, events, completed work, open actions, and anything the next shift needs to know…")
                            .foregroundStyle(.tertiary).padding(20).allowsHitTesting(false)
                    }
                }
        }
    }

    private var voiceControls: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    if speech.isListening { await speech.stop() } else { await speech.start() }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                        .frame(width: 34, height: 34)
                        .background(speech.isListening ? CailynTheme.urgent : CailynTheme.champagne, in: Circle())
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(speech.isListening ? "STOP & TRANSCRIBE" : "START PRIVATE TRANSCRIPTION")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                        Text(voiceStatusText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if speech.isListening {
                        HStack(spacing: 3) {
                            ForEach(0..<5, id: \.self) { index in
                                Capsule().fill(CailynTheme.champagneGlow).frame(width: 3, height: max(5, CGFloat(speech.audioLevel) * CGFloat(12 + index * 5)))
                            }
                        }.frame(height: 30)
                    }
                }
                .padding(12)
                .background(CailynTheme.paperRaised, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(speech.isBusy && !speech.isListening)
            .accessibilityIdentifier("capture.voice.toggle")
        }
    }

    private var voiceStatusText: String {
        switch speech.state {
        case .idle: "On-device only. No recording is kept."
        case .requestingPermission: "Checking private speech access…"
        case .listening: "On-device · stops after 2 seconds of silence"
        case .finishing: "Finalizing transcript before review…"
        case .unavailable(let message), .failed(let message): message
        }
    }

    private var privacyNote: some View {
        Label(mode == .turnover
              ? "Audio is never stored. The original text transcript is retained beside the organized turnover so facts can be verified."
              : "Nothing is created or scheduled until you approve the interpretation. Voice audio is never stored.",
              systemImage: "lock.shield")
            .font(.footnote).foregroundStyle(.secondary)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(proposal == nil && turnoverDraft == nil ? "Cancel" : "Deny") {
                if proposal != nil || turnoverDraft != nil { resetInterpretation() } else { dismiss() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if proposal != nil {
                Button("Approve") { Task { await approveAction() } }.fontWeight(.semibold).disabled(isProcessing)
                    .accessibilityIdentifier("capture.approve")
            } else if turnoverDraft != nil {
                Button("Approve") { approveTurnover() }.fontWeight(.semibold).disabled(isProcessing)
                    .accessibilityIdentifier("capture.approve.turnover")
            } else {
                Button("Review") { review() }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing || speech.isBusy)
                    .accessibilityIdentifier("capture.review")
            }
        }
    }

    private func review(capturedText override: String? = nil) {
        isFocused = false
        isProcessing = true
        let capturedText = override ?? text
        Task {
            if mode == .action {
                proposal = await intelligence.proposeAction(from: capturedText, people: people.map(\.displayName), assets: assets.map(\.name), now: .now)
            } else {
                turnoverDraft = await intelligence.organizeTurnover(from: capturedText, people: people.map(\.displayName), now: .now)
            }
            isProcessing = false
        }
    }

    private func approveAction() async {
        guard let proposal else { return }
        isProcessing = true
        do {
            let receipt = try await alerts.schedule(title: proposal.title, notes: proposal.originalText, at: proposal.dueAt, kind: proposal.alertKind)
            let person = people.first { $0.displayName.caseInsensitiveCompare(proposal.personName ?? "") == .orderedSame }
            let asset = assets.first { $0.name == proposal.assetName }
            let action = CailynAction(
                title: proposal.title,
                details: proposal.originalText,
                priority: proposal.priority,
                status: proposal.status,
                dueAt: proposal.dueAt,
                followUpAt: proposal.status == .waiting ? proposal.dueAt : nil,
                waitingSince: proposal.status == .waiting ? .now : nil,
                source: source == .voice ? "Voice Capture" : "Typed Capture",
                alertKind: receipt?.kind ?? .none,
                alertIdentifier: receipt?.identifier,
                alertScheduledAt: receipt?.scheduledAt,
                person: person,
                asset: asset
            )
            context.insert(action)
            var logText = "Captured action: \(action.title)"
            if let note = receipt?.note { logText += ". \(note)" }
            context.insert(CailynLogEntry(text: logText, kind: .action, actionID: action.id))
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isProcessing = false
        }
    }

    private func approveTurnover() {
        guard let draft = turnoverDraft else { return }
        let note = CailynTurnoverNote(
            title: draft.title,
            source: source,
            rawTranscript: draft.rawTranscript,
            overview: draft.overview,
            unitStatus: draft.unitStatus,
            events: draft.events,
            abnormalConditions: draft.abnormalConditions,
            completedWork: draft.completedWork,
            openActions: draft.openActions,
            waitingOn: draft.waitingOn,
            upcomingWork: draft.upcomingWork,
            safetyNotes: draft.safetyNotes,
            uncertainties: draft.uncertainties
        )
        context.insert(note)
        for candidate in draft.actionCandidates where candidate.isSelected {
            let person = people.first { $0.displayName.caseInsensitiveCompare(candidate.personName ?? "") == .orderedSame }
            context.insert(CailynAction(title: candidate.title, details: "Created from \(draft.title)", priority: candidate.dueAt == nil ? .planned : .today, dueAt: candidate.dueAt, source: "Shift Turnover", person: person))
        }
        context.insert(CailynLogEntry(text: "Approved shift turnover: \(draft.title)", kind: .manual))
        do { try context.save(); dismiss() } catch { errorMessage = error.localizedDescription }
    }

    private func resetInterpretation() {
        proposal = nil
        turnoverDraft = nil
        speech.reset(keepingTranscript: true)
    }
}

private struct ActionProposalEditor: View {
    @Binding var proposal: CaptureProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: "REVIEW BEFORE COMMIT", trailing: proposal.confidence < 0.75 ? "CHECK DETAILS" : "READY")
            VStack(alignment: .leading, spacing: 6) {
                Text("ACTION").reviewLabel()
                TextField("Action", text: $proposal.title, axis: .vertical).font(.headline)
            }
            Divider()
            if let person = proposal.personName { ReviewValue(label: "PERSON", value: person) }
            if let asset = proposal.assetName { ReviewValue(label: "ASSET", value: asset) }
            Toggle("Include date and time", isOn: Binding(get: { proposal.dueAt != nil }, set: { proposal.dueAt = $0 ? Calendar.current.date(byAdding: .hour, value: 1, to: .now) : nil }))
            if proposal.dueAt != nil {
                DatePicker("Due", selection: Binding(get: { proposal.dueAt ?? .now }, set: { proposal.dueAt = $0 }), displayedComponents: [.date, .hourAndMinute])
            }
            Picker("Alert", selection: $proposal.alertKind) {
                ForEach(ActionAlertKind.allCases) { Text($0.label).tag($0) }
            }
            Picker("Priority", selection: $proposal.priority) {
                ForEach(ActionPriority.allCases) { Text("\($0.code) · \($0.label)").tag($0) }
            }
            if !proposal.interpretationNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Confirm these details", systemImage: "exclamationmark.triangle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(CailynTheme.champagneGlow)
                    ForEach(proposal.interpretationNotes, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                }
                .padding(12).background(CailynTheme.champagneGlow.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            }
            DisclosureGroup("Original capture") { Text(proposal.originalText).font(.footnote).foregroundStyle(.secondary).padding(.top, 8) }
        }
        .cailynSurface()
    }
}

private struct TurnoverDraftEditor: View {
    @Binding var draft: TurnoverDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: "DRAFT TURNOVER", trailing: "NOT SAVED")
            TextField("Title", text: $draft.title).font(.headline)
            TurnoverField(title: "OVERVIEW", text: $draft.overview)
            TurnoverField(title: "UNIT / ASSET STATUS", text: $draft.unitStatus)
            TurnoverField(title: "EVENTS", text: $draft.events)
            TurnoverField(title: "ABNORMAL CONDITIONS", text: $draft.abnormalConditions)
            TurnoverField(title: "WORK COMPLETED", text: $draft.completedWork)
            TurnoverField(title: "OPEN ACTIONS", text: $draft.openActions)
            TurnoverField(title: "WAITING ON", text: $draft.waitingOn)
            TurnoverField(title: "UPCOMING WORK", text: $draft.upcomingWork)
            TurnoverField(title: "SAFETY / OPERATIONAL NOTES", text: $draft.safetyNotes)
            TurnoverField(title: "NEEDS CONFIRMATION", text: $draft.uncertainties)

            if !draft.actionCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PROPOSED ACTIONS").reviewLabel()
                    Text("Only selected items will be added to Actions when you approve the turnover.").font(.caption).foregroundStyle(.secondary)
                    ForEach($draft.actionCandidates) { $candidate in
                        Toggle(isOn: $candidate.isSelected) {
                            VStack(alignment: .leading) {
                                Text(candidate.title)
                                if let due = candidate.dueAt { Text(due.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                .padding(12).background(CailynTheme.champagne.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            DisclosureGroup("Original transcript · preserved exactly as text") {
                Text(draft.rawTranscript).font(.footnote).textSelection(.enabled).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
        .cailynSurface()
    }
}

private struct TurnoverField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).reviewLabel()
            TextField("None captured", text: $text, axis: .vertical).lineLimit(1...8)
        }
    }
}

private struct ReviewValue: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).reviewLabel().frame(width: 65, alignment: .leading)
            Text(value).font(.subheadline.weight(.medium))
            Spacer()
        }
    }
}

private extension View {
    func reviewLabel() -> some View { font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary) }
}
