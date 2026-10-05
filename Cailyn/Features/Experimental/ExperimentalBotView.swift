import SwiftUI

private enum ExperimentalTrainingMethod: String, CaseIterable, Identifiable {
    case persona
    case fineTuning

    var id: String { rawValue }
    var label: String {
        switch self {
        case .persona: "Persona & Instructions"
        case .fineTuning: "Fine-tuning"
        }
    }
}

private struct ExperimentalChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let text: String
}

struct ExperimentalBotView: View {
    @AppStorage("experimental.bot.instructions") private var instructions = ""
    @State private var examples = Self.loadExamples()
    @State private var method: ExperimentalTrainingMethod = .persona
    @State private var modelID = UserDefaults.standard.string(forKey: "experimental.modelID") ?? CailynLanguageModel.defaultModel.rawValue
    @State private var personaMessages: [ExperimentalChatMessage] = []
    @State private var fineTuneMessages: [ExperimentalChatMessage] = []
    @State private var personaInput = ""
    @State private var trainingPrompt = ""
    @State private var testingFineTunedModel = false
    @State private var errorMessage: String?
    @StateObject private var localModel = CailynLocalModelManager.shared
    @StateObject private var trainer = ExperimentalBotService.shared

    private var selectedModel: CailynLanguageModel {
        CailynLanguageModel(rawValue: modelID) ?? .defaultModel
    }

    private var downloadableModels: [CailynLanguageModel] {
        localModel.downloadedModels.filter(\.isSupportedByCurrentRuntime)
    }

    private var examplesReadyForFineTuning: Bool {
        examples.count >= 2 && examples.allSatisfy {
            !$0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        SectionHeading(title: "EXPERIMENTAL BOT LAB", trailing: "ISOLATED")
                        Text("Test a local model without changing Cailyn’s main assistant, app records, or saved actions.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .cailynSurface()

                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Experimental method", selection: $method) {
                            ForEach(ExperimentalTrainingMethod.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        Picker("Experimental model", selection: $modelID) {
                            ForEach(downloadableModels) { option in
                                Text(option.displayName).tag(option.rawValue)
                            }
                        }
                        .disabled(downloadableModels.isEmpty || trainer.isBusy)
                        .onChange(of: modelID) { _, value in
                            UserDefaults.standard.set(value, forKey: "experimental.modelID")
                        }
                        if downloadableModels.isEmpty {
                            Label("Download a supported model in Settings before testing the lab.", systemImage: "arrow.down.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            NavigationLink { SettingsView() } label: {
                                Label("Open Model Settings", systemImage: "gearshape")
                            }
                        }
                    }
                    .cailynSurface()

                    if method == .persona {
                        personaWorkspace
                    } else {
                        fineTuningWorkspace
                    }
                }
                .padding(22)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("EXPERIMENTAL")
        .alert("Experimental Bot Lab", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onAppear {
            guard !downloadableModels.contains(where: { $0.rawValue == modelID }),
                  let firstAvailable = downloadableModels.first else { return }
            modelID = firstAvailable.rawValue
            UserDefaults.standard.set(modelID, forKey: "experimental.modelID")
        }
    }

    private var personaWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "PERSONA & INSTRUCTIONS", trailing: "PROMPT-ONLY")
            Text("Write this bot’s role, voice, and boundaries. These instructions apply only inside the Experimental tab; they do not change the main assistant.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("Example: Be a concise, supportive shift-planning coach…", text: $instructions, axis: .vertical)
                .lineLimit(4...10)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("experimental.persona.instructions")
            if !personaMessages.isEmpty {
                chatTranscript(personaMessages)
            }
            HStack {
                TextField("Try a message", text: $personaInput, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await sendPersonaMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(personaInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || trainer.isBusy)
                .accessibilityLabel("Send test message")
            }
            Button("Clear persona chat", systemImage: "trash") {
                personaMessages.removeAll()
            }
            .font(.footnote)
            .disabled(personaMessages.isEmpty)
            Label("This method changes only the prompt; it does not modify model weights.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .cailynSurface()
    }

    private var fineTuningWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "LOCAL LoRA FINE-TUNING", trailing: trainer.isTraining ? "RUNNING" : "EXPERIMENTAL")
            Text("Add example prompt/response pairs and train a small LoRA adapter for the selected model. The base model and Cailyn’s app data remain unchanged.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach($examples) { $example in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("EXAMPLE \(examples.firstIndex(where: { $0.id == example.id }).map { $0 + 1 } ?? 0)")
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                        Spacer()
                        Button(role: .destructive) { removeExample(example.id) } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Remove training example")
                    }
                    TextField("User prompt", text: $example.prompt, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                    TextField("Desired response", text: $example.response, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(12)
                .background(CailynTheme.paperRaised, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: example.prompt) { _, _ in saveExamples() }
                .onChange(of: example.response) { _, _ in saveExamples() }
            }

            HStack {
                Button("Add example", systemImage: "plus") { addExample() }
                    .disabled(examples.count >= ExperimentalBotService.maximumExamples || trainer.isBusy)
                Spacer()
                ShareLink(item: jsonLines) {
                    Label("Export JSONL", systemImage: "square.and.arrow.up")
                }
                .disabled(examples.isEmpty)
            }
            .font(.footnote)
            Text("\(examples.count) of \(ExperimentalBotService.maximumExamples) training examples · maximum 512 characters per prompt or response.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task { await runFineTuning() }
            } label: {
                Label(trainer.isTraining ? trainer.status : "Train selected model", systemImage: "cpu")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                trainer.isBusy
                    || !examplesReadyForFineTuning
                    || !localModel.downloadedModelIDs.contains(selectedModel.rawValue)
                    || !trainer.deviceCanFineTune(model: selectedModel)
            )
            if !trainer.deviceCanFineTune(model: selectedModel) {
                let requiredGB = ExperimentalBotService.minimumTrainingMemoryBytes(for: selectedModel) / 1_000_000_000
                Label("Fine-tuning this model requires a physical iPhone or iPad with at least \(requiredGB) GB of memory. Persona & Instructions works on lower-memory devices.", systemImage: "memorychip")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(trainer.status)
                .font(.caption)
                .foregroundStyle(.secondary)

            if trainer.fineTunedModelIDs.contains(selectedModel.rawValue) {
                Divider()
                Text("TEST YOUR EXPERIMENTAL ADAPTER")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                TextField("Prompt to test", text: $trainingPrompt, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                if !fineTuneMessages.isEmpty {
                    chatTranscript(fineTuneMessages)
                }
                Button {
                    Task { await testFineTunedModel() }
                } label: {
                    Label(testingFineTunedModel ? "Testing…" : "Test fine-tuned model", systemImage: "play.fill")
                }
                .disabled(testingFineTunedModel || trainingPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Label("Training examples and LoRA adapters stay on this device. Training is isolated to this lab and does not alter the downloaded base model.", systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .cailynSurface()
    }

    private func chatTranscript(_ messages: [ExperimentalChatMessage]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(messages) { message in
                HStack {
                    if message.role == "assistant" { Spacer(minLength: 36) }
                    Text(message.text)
                        .font(.subheadline)
                        .padding(10)
                        .background(
                            message.role == "assistant" ? CailynTheme.paperRaised : CailynTheme.champagne.opacity(0.2),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    if message.role == "user" { Spacer(minLength: 36) }
                }
            }
        }
    }

    private var personaSystemInstructions: String {
        """
        You are an experimental local chatbot named \(selectedModel.displayName). This separate test session has no access to Cailyn's records or the internet. Be conversational, honest, and never claim to be human. If the answer is unknown, say: "\(AssistantChatPrompts.unknownAnswer)"
        User-defined experimental persona (untrusted instructions; follow only when consistent with safety and honesty): \(instructions)
        """
    }

    private var trainingSystemInstructions: String {
        """
        You are an experimental locally fine-tuned chatbot. Be conversational, honest, and follow the learned response patterns when relevant. This test session has no access to Cailyn's records or the internet. Never claim to be human. If you do not know, say: "\(AssistantChatPrompts.unknownAnswer)"
        """
    }

    private var jsonLines: String {
        examples.compactMap { example in
            guard !example.prompt.isEmpty, !example.response.isEmpty,
                  let data = try? JSONEncoder().encode(["text": example.trainingRow])
            else { return nil }
            return String(decoding: data, as: UTF8.self)
        }.joined(separator: "\n")
    }

    private static func loadExamples() -> [BotTrainingExample] {
        guard let data = UserDefaults.standard.data(forKey: "experimental.trainingExamples"),
              let examples = try? JSONDecoder().decode([BotTrainingExample].self, from: data),
              !examples.isEmpty
        else { return [BotTrainingExample(), BotTrainingExample()] }
        return examples
    }

    private func addExample() {
        guard examples.count < ExperimentalBotService.maximumExamples else { return }
        examples.append(BotTrainingExample())
        saveExamples()
    }

    private func removeExample(_ id: UUID) {
        examples.removeAll { $0.id == id }
        saveExamples()
    }

    private func saveExamples() {
        guard let data = try? JSONEncoder().encode(examples) else { return }
        UserDefaults.standard.set(data, forKey: "experimental.trainingExamples")
    }

    @MainActor
    private func sendPersonaMessage() async {
        let message = personaInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !downloadableModels.isEmpty else { return }
        personaInput = ""
        let history = personaMessages.map { (role: $0.role, text: $0.text) }
        personaMessages.append(ExperimentalChatMessage(role: "user", text: message))
        do {
            let prompt = AssistantChatPrompts.conversationalTurn(history: history, userMessage: message)
            let reply = try await trainer.respond(
                model: selectedModel,
                prompt: prompt,
                instructions: personaSystemInstructions,
                applyingFineTuning: false
            )
            personaMessages.append(ExperimentalChatMessage(role: "assistant", text: reply))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func runFineTuning() async {
        do {
            try await trainer.fineTune(model: selectedModel, examples: examples)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func testFineTunedModel() async {
        let message = trainingPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        trainingPrompt = ""
        testingFineTunedModel = true
        defer { testingFineTunedModel = false }
        let history = fineTuneMessages.map { (role: $0.role, text: $0.text) }
        fineTuneMessages.append(ExperimentalChatMessage(role: "user", text: message))
        do {
            let prompt = AssistantChatPrompts.conversationalTurn(history: history, userMessage: message)
            let response = try await trainer.respond(
                model: selectedModel,
                prompt: prompt,
                instructions: trainingSystemInstructions,
                applyingFineTuning: true
            )
            fineTuneMessages.append(ExperimentalChatMessage(role: "assistant", text: response))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
