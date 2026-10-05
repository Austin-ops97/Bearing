import AVFoundation
import SwiftUI

struct VoiceSettingsView: View {
    @EnvironmentObject private var voice: VoiceEngine
    @AppStorage(VoicePreferenceKey.mode) private var modeRaw = VoiceMode.importantOnly.rawValue
    @AppStorage(VoicePreferenceKey.detail) private var detailRaw = VerbalDetail.brief.rawValue
    @AppStorage(VoicePreferenceKey.policy) private var policyRaw = SpeechPolicy.importantOnly.rawValue
    @AppStorage(VoicePreferenceKey.identifier) private var voiceIdentifier = "best"
    @AppStorage(VoicePreferenceKey.rate) private var rate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @State private var voiceRevision = 0
    @State private var personalVoiceStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus

    var body: some View {
        Form {
            Section {
                Picker("Output Mode", selection: $modeRaw) {
                    ForEach(VoiceMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Preferred Voice", selection: $voiceIdentifier) {
                    Text("Best Available · Premium First").tag("best")
                    ForEach(voice.availableVoices, id: \.identifier) { candidate in
                        Text("\(candidate.name) · \(candidate.language) · \(qualityLabel(candidate.quality))").tag(candidate.identifier)
                    }
                    .id(voiceRevision)
                }
                Picker("Verbal Detail", selection: $detailRaw) {
                    ForEach(VerbalDetail.allCases) { Text($0.label).tag($0.rawValue) }
                }
                VStack(alignment: .leading) {
                    Text("Speaking Rate")
                    Slider(value: $rate, in: 0.35...0.6)
                }
            } header: { Text("Voice") } footer: {
                Text("Cailyn uses Apple’s current on-device speech system. Best Available automatically prefers an installed Premium voice, then Enhanced, for your language. Apple does not expose the private Siri voice to third-party apps.")
            }

            Section {
                LabeledContent("Personal Voice", value: personalVoiceStatusLabel)
                if personalVoiceStatus == .notDetermined {
                    Button("Allow Personal Voice") {
                        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                            Task { @MainActor in
                                personalVoiceStatus = status
                                voiceRevision += 1
                            }
                        }
                    }
                }
            } header: { Text("Latest Apple Voices") } footer: {
                Text("Premium and Personal voices only appear after they are installed or authorized in iOS Settings. Cailyn detects changes automatically.")
            }

            Section("Speech Policy") {
                Picker("Context", selection: $policyRaw) {
                    ForEach(SpeechPolicy.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Button("Mute for 30 Minutes") { voice.mute(for: 30 * 60) }
                Button("Resume Speech") { voice.clearMute() }
            }

            Section("Spoken Categories") {
                ForEach(SpeechCategory.allCases) { category in CategoryToggle(category: category) }
            }

            Section {
                Button {
                    voice.speak(.init(
                        key: "voice-test-\(UUID().uuidString)",
                        category: .actions,
                        priority: .deadline,
                        brief: "Cailyn voice check.",
                        normal: "Cailyn voice check. Spoken awareness is ready.",
                        detailed: "Cailyn voice check. Spoken awareness is configured and ready to provide selected operational alerts.",
                        cooldown: 0
                    ), userInitiated: true)
                } label: { Label("Test Voice", systemImage: "speaker.wave.2") }
                if voice.isSpeaking { Button("Stop Speaking", role: .destructive) { voice.stop() } }
            }
        }
        .navigationTitle("VOICE")
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            voiceRevision += 1
            personalVoiceStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
        }
    }

    private func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Standard"
        }
    }

    private var personalVoiceStatusLabel: String {
        switch personalVoiceStatus {
        case .authorized: "Authorized"
        case .denied: "Not Allowed"
        case .notDetermined: "Not Requested"
        case .unsupported: "Not Supported"
        @unknown default: "Unavailable"
        }
    }
}

private struct CategoryToggle: View {
    let category: SpeechCategory
    @AppStorage private var isEnabled: Bool

    init(category: SpeechCategory) {
        self.category = category
        _isEnabled = AppStorage(wrappedValue: true, VoicePreferenceKey.category(category))
    }

    var body: some View { Toggle(category.label, isOn: $isEnabled) }
}

struct SettingsView: View {
    @AppStorage("appearance.mode") private var appearanceMode = AppAppearance.system.rawValue
    @AppStorage("intelligence.modelPreference") private var modelPreference = AIModelPreference.automatic.rawValue
    @State private var intelligenceStatus = HybridIntelligenceService.runtimeStatus()
    @StateObject private var localModel = CailynLocalModelManager.shared
    @State private var modelToRemove: CailynLanguageModel?

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Mode", selection: $appearanceMode) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            Section("Awareness") {
                NavigationLink { VoiceSettingsView() } label: { Label("Voice & Verbal Awareness", systemImage: "waveform") }
            }
            Section {
                Picker("Model Route", selection: $modelPreference) {
                    ForEach(AIModelPreference.allCases) { Text($0.label).tag($0.rawValue) }
                }
                LabeledContent("Current Status", value: intelligenceStatus.title)
                Text(intelligenceStatus.detail).font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("Intelligence")
            } footer: {
                Text("Cailyn always runs deterministic extraction first. The selected on-device model may classify or normalize the remaining data; results are checked locally and never committed without your approval.")
            }
            Section {
                Picker("Selected Model", selection: Binding(
                    get: { localModel.selectedModel.rawValue },
                    set: { if let model = CailynLanguageModel(rawValue: $0) { localModel.selectModel(model) } }
                )) {
                    ForEach(CailynLanguageModel.allCases.filter(\.isSupportedByCurrentRuntime)) { model in
                        Text(model.displayName).tag(model.rawValue)
                    }
                }
                LabeledContent("Status", value: localModel.status)
                LabeledContent("Downloaded Models", value: "\(localModel.downloadedModelIDs.count) of \(CailynLanguageModel.maximumDownloadedModels)")
                if localModel.isLoading {
                    ProgressView(value: localModel.progress)
                    Text("Downloading or loading one model at a time").font(.footnote).foregroundStyle(.secondary)
                }
                Button(localModel.isLoaded ? "Selected Model Ready" : localModel.selectedModelIsDownloaded ? "Load Selected Model" : "Download & Load Selected Model") {
                    Task { await localModel.loadModel() }
                }
                .disabled(!localModel.deviceSupportsModel || localModel.isLoaded || localModel.isLoading || (!localModel.selectedModelIsDownloaded && localModel.remainingDownloadSlots == 0))
                Link("Open selected model on Hugging Face", destination: URL(string: "https://huggingface.co/\(localModel.selectedModel.repositoryID)")!)
                if !localModel.deviceSupportsModel {
                    Label(localModel.deviceSupportMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("On-Device Models")
            } footer: {
                Text("Models are downloaded from Hugging Face and run locally. Cailyn keeps at most five model downloads; remove one below to make room. Only one model is loaded into memory at a time. Model terms differ—review each model card and license before downloading.")
            }
            Section("Model Library") {
                ForEach(CailynLanguageModel.allCases) { model in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button {
                                localModel.selectModel(model)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(model.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(model.licenseSummary) · 4-bit MLX")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!model.isSupportedByCurrentRuntime)
                            if model == localModel.selectedModel {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(CailynTheme.champagne)
                            }
                        }
                        if let note = model.runtimeNote {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                            Link("View model card", destination: URL(string: "https://huggingface.co/\(model.repositoryID)")!)
                                .font(.caption)
                        } else {
                            HStack {
                                Link("Model card", destination: URL(string: "https://huggingface.co/\(model.repositoryID)")!)
                                    .font(.caption)
                                Spacer()
                                if localModel.downloadedModelIDs.contains(model.rawValue) {
                                    Label("Downloaded", systemImage: "checkmark.circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Button("Remove", role: .destructive) {
                                        modelToRemove = model
                                    }
                                    .font(.caption)
                                    .disabled(localModel.isLoading)
                                } else {
                                    Button("Download & Load") {
                                        localModel.selectModel(model)
                                        Task { await localModel.loadModel() }
                                    }
                                    .font(.caption.weight(.semibold))
                                    .disabled(
                                        !localModel.deviceSupportsModel
                                            || localModel.isLoading
                                            || localModel.remainingDownloadSlots == 0
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            Section("Privacy") {
                Label("Cailyn’s database remains on this device", systemImage: "lock.shield")
                Text("Capture intelligence runs on-device. Cailyn does not send capture text to Private Cloud Compute or another cloud AI service. No audio recording is retained or uploaded.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("SETTINGS")
        .onAppear {
            refreshIntelligenceStatus()
            localModel.refreshDownloadedModels()
        }
        .onChange(of: modelPreference) { _, _ in refreshIntelligenceStatus() }
        .alert("Local Model Could Not Be Loaded", isPresented: Binding(
            get: { localModel.errorMessage != nil },
            set: { if !$0 { localModel.dismissError() } }
        )) {
            Button("OK", role: .cancel) { localModel.dismissError() }
        } message: {
            Text(localModel.errorMessage ?? "Unknown error")
        }
        .confirmationDialog(
            "Remove \(modelToRemove?.displayName ?? "model")?",
            isPresented: Binding(
                get: { modelToRemove != nil },
                set: { if !$0 { modelToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Downloaded Files", role: .destructive) {
                guard let model = modelToRemove else { return }
                do {
                    try localModel.removeDownloadedModel(model)
                } catch {
                    localModel.reportError(error)
                }
                modelToRemove = nil
            }
            Button("Cancel", role: .cancel) { modelToRemove = nil }
        } message: {
            Text("This deletes the local model files from this device. You can download the model again later.")
        }
    }

    private func refreshIntelligenceStatus() {
        intelligenceStatus = HybridIntelligenceService.runtimeStatus(
            preference: AIModelPreference(rawValue: modelPreference) ?? .automatic
        )
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
