import Foundation

#if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace) && canImport(Tokenizers) && canImport(MLXOptimizers)
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXOptimizers
import Tokenizers
#endif

@MainActor
final class ExperimentalBotService: ObservableObject {
    static let shared = ExperimentalBotService()
    nonisolated static let minimumTrainingMemoryBytes: UInt64 = 8_000_000_000
    nonisolated static let maximumExamples = 24
    nonisolated static let trainingIterations = 20

    @Published private(set) var isTraining = false
    @Published private(set) var isBusy = false
    @Published private(set) var status = "Fine-tuning has not been run"

    private init() {}

    func deviceCanFineTune(model: CailynLanguageModel) -> Bool {
        #if os(iOS) && !targetEnvironment(simulator)
        ProcessInfo.processInfo.physicalMemory >= Self.minimumTrainingMemoryBytes(for: model)
        #else
        false
        #endif
    }

    nonisolated static func minimumTrainingMemoryBytes(for model: CailynLanguageModel) -> UInt64 {
        switch model {
        case .gemma3, .qwen3: 12_000_000_000
        default: minimumTrainingMemoryBytes
        }
    }

    var fineTunedModelIDs: Set<String> {
        Set(CailynLanguageModel.allCases.filter { adapterDirectory(for: $0) != nil }.map(\.rawValue))
    }

    func fineTune(model: CailynLanguageModel, examples: [BotTrainingExample]) async throws {
        guard !isBusy else { throw ExperimentalBotError.busy }
        guard model.isSupportedByCurrentRuntime else { throw ExperimentalBotError.unsupportedModel }
        guard examples.count >= 2, examples.count <= Self.maximumExamples else {
            throw ExperimentalBotError.exampleCount
        }
        guard examples.allSatisfy({
            !$0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.prompt.count <= 512
                && $0.response.count <= 512
        }) else {
            throw ExperimentalBotError.exampleTooLong
        }
        #if os(iOS) && !targetEnvironment(simulator)
        guard deviceCanFineTune(model: model) else { throw ExperimentalBotError.insufficientMemory(model) }
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace) && canImport(Tokenizers) && canImport(MLXOptimizers)
        isTraining = true
        isBusy = true
        status = "Preparing an isolated LoRA fine-tuning run…"
        defer {
            isTraining = false
            isBusy = false
            MLX.Memory.clearCache()
        }

        try CailynLocalModelManager.shared.unloadForExperimentalWork()
        let outputDirectory = try Self.adapterDirectory(for: model, create: true)
        let adapterURL = outputDirectory.appendingPathComponent("adapters.safetensors")
        let config = LoRAConfiguration(
            numLayers: 4,
            fineTuneType: .lora,
            loraParameters: .init(rank: 4, scale: 8, dropout: 0.05)
        )
        let trainingRows = examples.map {
            "User: \($0.prompt.trimmingCharacters(in: .whitespacesAndNewlines))\nAssistant: \($0.response.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        let modelContainer = try await MLXLMCommon.loadModelContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: ModelConfiguration(id: model.repositoryID)
        )
        status = "Training \(model.displayName) with \(examples.count) examples…"
        try await modelContainer.perform { modelContext in
            let languageModel = modelContext.model
            _ = try LoRAContainer.from(model: languageModel, configuration: config)
            let parameters = LoRATrain.Parameters(
                batchSize: 1,
                iterations: Self.trainingIterations,
                stepsPerReport: 1,
                stepsPerEval: Self.trainingIterations,
                validationBatches: 1,
                saveEvery: Self.trainingIterations,
                adapterURL: adapterURL
            )
            try LoRATrain.train(
                model: languageModel,
                train: trainingRows,
                validate: trainingRows,
                optimizer: Adam(learningRate: 1e-5),
                tokenizer: modelContext.tokenizer,
                parameters: parameters
            ) { _ in .more }
            try LoRATrain.saveLoRAWeights(model: languageModel, url: adapterURL)
        }
        let configurationData = try JSONEncoder().encode(config)
        try configurationData.write(
            to: outputDirectory.appendingPathComponent("adapter_config.json"),
            options: .atomic
        )
        status = "LoRA adapter trained for \(model.displayName) · isolated to Experimental"
        #else
        throw ExperimentalBotError.runtimeUnavailable
        #endif
        #else
        throw ExperimentalBotError.physicalDeviceRequired
        #endif
    }

    func respond(
        model: CailynLanguageModel,
        prompt: String,
        instructions: String,
        applyingFineTuning: Bool
    ) async throws -> String {
        guard !isBusy else { throw ExperimentalBotError.busy }
        guard prompt.count <= 8_000 else { throw ExperimentalBotError.promptTooLong }
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace) && canImport(Tokenizers) && canImport(MLXOptimizers)
        let adapterURL = applyingFineTuning ? adapterDirectory(for: model) : nil
        guard !applyingFineTuning || adapterURL != nil else { throw ExperimentalBotError.adapterNotFound }
        isBusy = true
        status = "Loading the isolated experimental model…"
        try CailynLocalModelManager.shared.unloadForExperimentalWork()
        defer {
            isBusy = false
            status = "Experimental model response complete"
            MLX.Memory.clearCache()
        }
        let modelContainer = try await MLXLMCommon.loadModelContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: ModelConfiguration(id: model.repositoryID)
        )
        return try await modelContainer.perform { modelContext in
            if applyingFineTuning {
                guard let directory = adapterURL else { throw ExperimentalBotError.adapterNotFound }
                let adapter = try LoRAContainer.from(directory: directory)
                try adapter.load(into: modelContext.model)
            }
            let session = ChatSession(
                modelContext,
                instructions: instructions,
                generateParameters: GenerateParameters(
                    maxTokens: 256,
                    maxKVSize: 1_024,
                    temperature: 0.7
                )
            )
            return try await session.respond(to: prompt)
        }
        #else
        throw ExperimentalBotError.runtimeUnavailable
        #endif
    }

    private func adapterDirectory(for model: CailynLanguageModel) -> URL? {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExperimentalBots", isDirectory: true)
            .appendingPathComponent(model.rawValue, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("adapters.safetensors").path),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("adapter_config.json").path)
        else { return nil }
        return directory
    }

    private static func adapterDirectory(for model: CailynLanguageModel, create: Bool) throws -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExperimentalBots", isDirectory: true)
            .appendingPathComponent(model.rawValue, isDirectory: true)
        if create { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        return directory
    }
}

struct BotTrainingExample: Codable, Identifiable, Equatable {
    var id: UUID
    var prompt: String
    var response: String

    init(id: UUID = UUID(), prompt: String = "", response: String = "") {
        self.id = id
        self.prompt = prompt
        self.response = response
    }

    var trainingRow: String {
        "User: \(prompt)\nAssistant: \(response)"
    }
}

enum ExperimentalBotError: LocalizedError {
    case busy
    case unsupportedModel
    case exampleCount
    case exampleTooLong
    case insufficientMemory(CailynLanguageModel)
    case physicalDeviceRequired
    case runtimeUnavailable
    case adapterNotFound
    case promptTooLong

    var errorDescription: String? {
        switch self {
        case .busy: return "An experimental model operation is already in progress."
        case .unsupportedModel: return "This model is not supported by the current MLX runtime."
        case .exampleCount: return "Add between 2 and \(ExperimentalBotService.maximumExamples) training examples."
        case .exampleTooLong: return "Each training prompt and response must be non-empty and no longer than 512 characters."
        case .insufficientMemory(let model):
            let requiredGB = ExperimentalBotService.minimumTrainingMemoryBytes(for: model) / 1_000_000_000
            return "Fine-tuning \(model.displayName) requires a physical device with at least \(requiredGB) GB of memory. Use the Persona & Instructions method on lower-memory devices."
        case .physicalDeviceRequired: return "On-device fine-tuning requires a supported physical iPhone or iPad; it is unavailable in Simulator."
        case .runtimeUnavailable: return "The MLX fine-tuning runtime is unavailable in this build."
        case .adapterNotFound: return "Train a LoRA adapter for this model in the Fine-tuning tab before testing it."
        case .promptTooLong: return "This experimental prompt is too long. Shorten it and try again."
        }
    }
}
