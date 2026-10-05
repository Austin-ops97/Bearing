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
                LabeledContent("Model", value: "Qwen2.5 3B · 4-bit")
                LabeledContent("Status", value: localModel.status)
                if localModel.isLoading {
                    ProgressView(value: localModel.progress)
                    Text("Several GB download · stored on this device").font(.footnote).foregroundStyle(.secondary)
                }
                if localModel.deviceSupportsModel {
                    Button(localModel.isLoaded ? "Model Ready" : "Download & Load Model") {
                        Task { await localModel.loadModel() }
                    }
                    .disabled(localModel.isLoaded || localModel.isLoading)
                    Link("View model on Hugging Face", destination: URL(string: "https://huggingface.co/\(CailynLocalModelManager.modelIdentifier)")!)
                } else {
                    Label(localModel.deviceSupportMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Optional Hugging Face Model")
            } footer: {
                Text("Qwen Research License · mlx-community/Qwen2.5-3B-Instruct-4bit. Tap Download & Load Model to fetch it directly from Hugging Face into Cailyn; no Hugging Face login is required. The multi-GB download needs internet once. This smaller model uses a 4-bit KV cache and bounded context to target supported physical devices with at least 4,000,000,000 bytes (4 GB) of memory. Actual availability still depends on memory used by iOS and other apps; Simulator is unsupported.")
            }
            Section("Privacy") {
                Label("Cailyn’s database remains on this device", systemImage: "lock.shield")
                Text("Capture intelligence runs on-device. Cailyn does not send capture text to Private Cloud Compute or another cloud AI service. No audio recording is retained or uploaded.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("SETTINGS")
        .onAppear { refreshIntelligenceStatus() }
        .onChange(of: modelPreference) { _, _ in refreshIntelligenceStatus() }
        .alert("Local Model Could Not Be Loaded", isPresented: Binding(
            get: { localModel.errorMessage != nil },
            set: { if !$0 { localModel.dismissError() } }
        )) {
            Button("OK", role: .cancel) { localModel.dismissError() }
        } message: {
            Text(localModel.errorMessage ?? "Unknown error")
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
