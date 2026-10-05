import Foundation

enum CailynLanguageModel: String, CaseIterable, Identifiable, Sendable {
    case ministral3
    case phi4Mini
    case lfm2
    case gemma3
    case qwen3
    case falcon3
    case qwen25

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ministral3: "Ministral 3 3B Instruct"
        case .phi4Mini: "Phi-4 Mini Instruct"
        case .lfm2: "LFM2 2.6B"
        case .gemma3: "Gemma 3 4B IT"
        case .qwen3: "Qwen3 4B"
        case .falcon3: "Falcon3 3B Instruct"
        case .qwen25: "Qwen2.5 3B Instruct"
        }
    }

    var repositoryID: String {
        switch self {
        case .ministral3: "mlx-community/Ministral-3-3B-Instruct-2512-4bit"
        case .phi4Mini: "mlx-community/Phi-4-mini-instruct-4bit"
        case .lfm2: "mlx-community/LFM2-2.6B-4bit"
        case .gemma3: "mlx-community/gemma-3-4b-it-4bit"
        case .qwen3: "mlx-community/Qwen3-4B-Instruct-2507-4bit"
        case .falcon3: "mlx-community/Falcon3-3B-Instruct-4bit"
        case .qwen25: "mlx-community/Qwen2.5-3B-Instruct-4bit"
        }
    }

    var licenseSummary: String {
        switch self {
        case .ministral3: "Apache 2.0"
        case .phi4Mini: "MIT"
        case .lfm2: "LiquidAI license"
        case .gemma3: "Gemma terms"
        case .qwen3: "Apache 2.0"
        case .falcon3: "Falcon license"
        case .qwen25: "Qwen Research License"
        }
    }

    var isSupportedByCurrentRuntime: Bool { true }

    var runtimeNote: String? { nil }

    static let defaultModel: Self = .qwen25
    static let maximumDownloadedModels = 5

    nonisolated static func canDownloadModel(downloadedCount: Int, isAlreadyDownloaded: Bool) -> Bool {
        isAlreadyDownloaded || (downloadedCount >= 0 && downloadedCount < maximumDownloadedModels)
    }
}
