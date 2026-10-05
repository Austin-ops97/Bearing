import SwiftUI

struct InitialSetupView: View {
    @AppStorage(PersonalizationKey.name) private var name = ""
    @AppStorage(PersonalizationKey.age) private var age = ""
    @AppStorage(PersonalizationKey.tone) private var toneRaw = AssistantTone.professional.rawValue
    @AppStorage(PersonalizationKey.completedOnboarding) private var didCompleteSetup = false
    @Environment(\.dismiss) private var dismiss

    private let isEditing: Bool

    init(isEditing: Bool = false) {
        self.isEditing = isEditing
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(isEditing ? "YOUR CAILYN" : "WELCOME TO CAILYN")
                                .font(.system(.caption, design: .rounded, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(CailynTheme.champagne)
                            Text(isEditing ? "Personalize your assistant." : "Let’s make this yours.")
                                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                            Text("This profile stays on this device and helps Cailyn tailor its language. You can change or clear it later.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            TextField("What should Cailyn call you?", text: $name)
                                .textContentType(.name)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("onboarding.name")
                            TextField("Age (optional)", text: $age)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("onboarding.age")
                            Text("Age is optional. Cailyn should only use it when directly relevant.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .cailynSurface()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("HOW SHOULD CAILYN SPEAK?")
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .tracking(1.1)
                            Picker("Assistant style", selection: $toneRaw) {
                                ForEach(AssistantTone.allCases) { tone in
                                    Text(tone.label).tag(tone.rawValue)
                                }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                            Text(toneDescription)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .cailynSurface()

                        Label("Your profile is used for on-device personalization. It is not shared with a cloud service.", systemImage: "lock.shield")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button(action: save) {
                            Text(isEditing ? "Save Preferences" : "Finish Setup")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isEditing && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("onboarding.finish")
                        if !isEditing && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("Continue without a name", action: save)
                                .font(.footnote)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(isEditing ? "PROFILE" : "INITIAL SETUP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private var toneDescription: String {
        switch AssistantTone(rawValue: toneRaw) ?? .professional {
        case .professional: "Polished, composed, and workplace-appropriate."
        case .warm: "Encouraging and attentive without being overly familiar."
        case .cozy: "Relaxed, gentle, and reassuring."
        case .direct: "Answer first, in plain language, without extra framing."
        case .wild: "Professional with occasional natural profanity when it fits; never aimed at a person."
        }
    }

    private func save() {
        didCompleteSetup = true
        if isEditing { dismiss() }
    }
}
