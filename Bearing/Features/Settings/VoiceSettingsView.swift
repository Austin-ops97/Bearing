import AVFoundation
import SwiftUI

struct VoiceSettingsView: View {
    @EnvironmentObject private var voice: VoiceEngine
    @AppStorage(VoicePreferenceKey.mode) private var modeRaw = VoiceMode.importantOnly.rawValue
    @AppStorage(VoicePreferenceKey.detail) private var detailRaw = VerbalDetail.brief.rawValue
    @AppStorage(VoicePreferenceKey.policy) private var policyRaw = SpeechPolicy.importantOnly.rawValue
    @AppStorage(VoicePreferenceKey.identifier) private var voiceIdentifier = "best"
    @AppStorage(VoicePreferenceKey.rate) private var rate = Double(AVSpeechUtteranceDefaultSpeechRate)

    var body: some View {
        Form {
            Section {
                Picker("Output Mode", selection: $modeRaw) {
                    ForEach(VoiceMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Preferred Voice", selection: $voiceIdentifier) {
                    Text("Best Available").tag("best")
                    ForEach(voice.availableVoices, id: \.identifier) { candidate in
                        Text("\(candidate.name) · \(candidate.language)").tag(candidate.identifier)
                    }
                }
                Picker("Verbal Detail", selection: $detailRaw) {
                    ForEach(VerbalDetail.allCases) { Text($0.label).tag($0.rawValue) }
                }
                VStack(alignment: .leading) {
                    Text("Speaking Rate")
                    Slider(value: $rate, in: 0.35...0.6)
                }
            } header: { Text("Voice") } footer: {
                Text("Bearing uses Apple’s local speech synthesizer in the foreground. Available voices are provided by this device.")
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
                        brief: "Bearing voice check.",
                        normal: "Bearing voice check. Spoken awareness is ready.",
                        detailed: "Bearing voice check. Spoken awareness is configured and ready to provide selected operational alerts.",
                        cooldown: 0
                    ), userInitiated: true)
                } label: { Label("Test Voice", systemImage: "speaker.wave.2") }
                if voice.isSpeaking { Button("Stop Speaking", role: .destructive) { voice.stop() } }
            }
        }
        .navigationTitle("VOICE")
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
    var body: some View {
        Form {
            Section("Awareness") {
                NavigationLink { VoiceSettingsView() } label: { Label("Voice & Verbal Awareness", systemImage: "waveform") }
            }
            Section("Privacy") {
                Label("Core data remains on this device", systemImage: "lock.shield")
                Text("Cloud services and external integrations are not connected.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("SETTINGS")
    }
}
