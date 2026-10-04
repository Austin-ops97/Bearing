@preconcurrency import AVFoundation
import Foundation

enum VoiceMode: String, CaseIterable, Identifiable {
    case off
    case importantOnly
    case selected
    case fullAssistant
    case custom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "OFF"
        case .importantOnly: "IMPORTANT ONLY"
        case .selected: "SELECTED"
        case .fullAssistant: "FULL ASSISTANT"
        case .custom: "CUSTOM"
        }
    }
}

enum VerbalDetail: String, CaseIterable, Identifiable {
    case brief
    case normal
    case detailed
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

enum SpeechPolicy: String, CaseIterable, Identifiable {
    case always
    case whileActive
    case activePlaybook
    case importantOnly
    case silent

    var id: String { rawValue }
    var label: String {
        switch self {
        case .always: "SPEAK ALWAYS"
        case .whileActive: "WHILE BEARING IS ACTIVE"
        case .activePlaybook: "DURING ACTIVE PLAYBOOK"
        case .importantOnly: "IMPORTANT ONLY"
        case .silent: "SILENT"
        }
    }
}

enum SpeechCategory: String, CaseIterable, Identifiable {
    case playbooks, actions, calendar, aiPlan, waiting, templates, timers, observations
    var id: String { rawValue }
    var label: String {
        switch self {
        case .playbooks: "Playbooks"
        case .actions: "Actions"
        case .calendar: "Calendar"
        case .aiPlan: "AI Plan"
        case .waiting: "Waiting On"
        case .templates: "Templates"
        case .timers: "Timers"
        case .observations: "AI Observations"
        }
    }
}

enum SpeechPriority: Int, Comparable {
    case critical = 0
    case playbookMilestone = 1
    case deadline = 2
    case planGuidance = 3
    case routine = 4
    case informational = 5
    static func < (lhs: SpeechPriority, rhs: SpeechPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct BearingSpeechEvent {
    let key: String
    let category: SpeechCategory
    let priority: SpeechPriority
    let brief: String
    let normal: String
    let detailed: String
    var cooldown: TimeInterval = 5 * 60

    func text(for detail: VerbalDetail) -> String {
        switch detail {
        case .brief: brief
        case .normal: normal
        case .detailed: detailed
        }
    }
}

enum VoicePreferenceKey {
    static let mode = "voice.mode"
    static let detail = "voice.detail"
    static let policy = "voice.policy"
    static let identifier = "voice.identifier"
    static let rate = "voice.rate"
    static let mutedUntil = "voice.mutedUntil"
    static func category(_ category: SpeechCategory) -> String { "voice.category.\(category.rawValue)" }
}

@MainActor
final class VoiceEngine: ObservableObject {
    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()
    private var spokenAt: [String: Date] = [:]
    private var pending: [(event: BearingSpeechEvent, utterance: AVSpeechUtterance)] = []
    private var currentPriority: SpeechPriority?
    private var monitorTask: Task<Void, Never>?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(Locale.current.language.languageCode?.identifier ?? "en") }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                return lhs.name < rhs.name
            }
    }

    func speak(_ event: BearingSpeechEvent, userInitiated: Bool = false) {
        guard userInitiated || shouldSpeak(event) else { return }
        if let last = spokenAt[event.key], Date.now.timeIntervalSince(last) < event.cooldown { return }

        let detail = VerbalDetail(rawValue: defaults.string(forKey: VoicePreferenceKey.detail) ?? "brief") ?? .brief
        let utterance = AVSpeechUtterance(string: event.text(for: detail))
        utterance.rate = Float(defaults.double(forKey: VoicePreferenceKey.rate))
        utterance.voice = selectedVoice()

        if event.priority <= .playbookMilestone,
           let currentPriority,
           event.priority < currentPriority,
           synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        spokenAt[event.key] = .now
        pending.append((event, utterance))
        pending.sort { $0.event.priority < $1.event.priority }
        startNextIfPossible()
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        pending.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        currentPriority = nil
        isSpeaking = false
    }

    func mute(for interval: TimeInterval) {
        defaults.set(Date.now.addingTimeInterval(interval).timeIntervalSince1970, forKey: VoicePreferenceKey.mutedUntil)
        stop()
    }

    func clearMute() { defaults.removeObject(forKey: VoicePreferenceKey.mutedUntil) }

    private func shouldSpeak(_ event: BearingSpeechEvent) -> Bool {
        let mode = VoiceMode(rawValue: defaults.string(forKey: VoicePreferenceKey.mode) ?? "importantOnly") ?? .importantOnly
        let policy = SpeechPolicy(rawValue: defaults.string(forKey: VoicePreferenceKey.policy) ?? "importantOnly") ?? .importantOnly
        if mode == .off || policy == .silent { return false }
        if defaults.double(forKey: VoicePreferenceKey.mutedUntil) > Date.now.timeIntervalSince1970 { return false }
        if mode == .importantOnly || policy == .importantOnly { return event.priority <= .deadline }
        if policy == .activePlaybook && event.category != .playbooks { return false }
        if mode == .selected || mode == .custom {
            return defaults.bool(forKey: VoicePreferenceKey.category(event.category))
        }
        return true
    }

    private func selectedVoice() -> AVSpeechSynthesisVoice? {
        if let identifier = defaults.string(forKey: VoicePreferenceKey.identifier), identifier != "best",
           let voice = AVSpeechSynthesisVoice(identifier: identifier) { return voice }
        return availableVoices.first
    }

    private func startNextIfPossible() {
        guard !synthesizer.isSpeaking, currentPriority == nil, !pending.isEmpty else { return }
        let next = pending.removeFirst()
        currentPriority = next.event.priority
        isSpeaking = true
        synthesizer.speak(next.utterance)

        monitorTask?.cancel()
        monitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while synthesizer.isSpeaking, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            currentPriority = nil
            isSpeaking = false
            startNextIfPossible()
        }
    }

    private func registerDefaults() {
        var values: [String: Any] = [
            VoicePreferenceKey.mode: VoiceMode.importantOnly.rawValue,
            VoicePreferenceKey.detail: VerbalDetail.brief.rawValue,
            VoicePreferenceKey.policy: SpeechPolicy.importantOnly.rawValue,
            VoicePreferenceKey.identifier: "best",
            VoicePreferenceKey.rate: Double(AVSpeechUtteranceDefaultSpeechRate)
        ]
        SpeechCategory.allCases.forEach { values[VoicePreferenceKey.category($0)] = true }
        defaults.register(defaults: values)
    }
}
