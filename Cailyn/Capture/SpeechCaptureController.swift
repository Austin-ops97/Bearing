import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechCaptureController: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case finishing
        case unavailable(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var completedTranscriptGeneration = 0

    private let audioInput = AudioInputEngine()
    private let silenceDetector = AudioSilenceDetector()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var committedTranscript = ""
    private var activeGeneration: UUID?
    private var sessionGeneration: UUID?
    private var lastTranscriptPublish = Date.distantPast
    private let requestRelay = AudioRequestRelay()
    private let meterGate = AudioMeterGate(minimumInterval: 0.1)

    var isListening: Bool { state == .listening }
    var isBusy: Bool { state == .requestingPermission || state == .listening || state == .finishing }

    func start(locale: Locale = .current) async {
        guard !isBusy else { return }
        await cleanup()
        let generation = UUID()
        activeGeneration = generation
        state = .requestingPermission
        let speechAllowed = await requestSpeechAuthorization()
        guard activeGeneration == generation else { return }
        guard speechAllowed else {
            state = .unavailable("Speech Recognition permission is required. Enable it in Settings to use private voice capture.")
            return
        }
        let microphoneAllowed = await requestMicrophoneAuthorization()
        guard activeGeneration == generation else { return }
        guard microphoneAllowed else {
            state = .unavailable("Microphone permission is required. Enable it in Settings to use voice capture.")
            return
        }

        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            state = .unavailable("On-device speech recognition is not available for this language on this device. Cailyn will not send this audio online.")
            return
        }

        do {
            sessionGeneration = try await AudioSessionCoordinator.shared.activate()
            transcript = ""
            committedTranscript = ""
            lastTranscriptPublish = .distantPast
            silenceDetector.reset()
            speechRecognizer = recognizer
            beginRecognitionCycle(with: recognizer, generation: generation)
            try await audioInput.start(
                relay: requestRelay,
                meter: meterGate,
                silenceDetector: silenceDetector,
                onMeter: { [weak self] level in
                    Task { @MainActor in
                        guard self?.activeGeneration == generation else { return }
                        self?.audioLevel = level
                    }
                },
                onSilence: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.activeGeneration == generation, self.state == .listening else { return }
                        await self.stop()
                    }
                }
            )
            state = .listening
        } catch {
            await cleanup(setIdle: false)
            state = .failed("Voice capture could not start: \(error.localizedDescription)")
        }
    }

    func stop() async {
        guard isListening else { return }
        state = .finishing
        await audioInput.stop()
        recognitionRequest?.endAudio()
        audioLevel = 0
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.state == .finishing else { return }
            await self.finishAndProcessTranscript()
        }
    }

    func cancel() {
        activeGeneration = nil
        state = .idle
        transcript = ""
        recognitionTask?.cancel()
        requestRelay.set(nil)
        Task { await cleanup() }
    }

    func reset(keepingTranscript: Bool = false) {
        activeGeneration = nil
        recognitionTask?.cancel()
        requestRelay.set(nil)
        if !keepingTranscript { transcript = "" }
        state = .idle
        Task { await cleanup() }
    }

    private func beginRecognitionCycle(with recognizer: SFSpeechRecognizer, generation: UUID) {
        guard activeGeneration == generation else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = ["shift turnover", "unit status", "follow-up", "workflow", "Cailyn"]
        recognitionRequest = request
        requestRelay.set(request)
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.activeGeneration == generation else { return }
                if let result {
                    let segment = result.bestTranscription.formattedString
                    let now = Date()
                    if result.isFinal || now.timeIntervalSince(self.lastTranscriptPublish) >= 0.15 {
                        self.transcript = Self.join(self.committedTranscript, segment)
                        self.lastTranscriptPublish = now
                    }
                    if result.isFinal {
                        if self.state == .finishing {
                            self.recognitionTask = nil
                            self.recognitionRequest = nil
                            await self.finishAndProcessTranscript()
                        } else if self.state == .listening {
                            self.committedTranscript = Self.join(self.committedTranscript, segment)
                            self.recognitionTask = nil
                            self.recognitionRequest = nil
                            self.beginRecognitionCycle(with: recognizer, generation: generation)
                        }
                    }
                }
                if let error, self.state != .finishing {
                    self.recognitionTask = nil
                    self.recognitionRequest = nil
                    self.state = .failed(error.localizedDescription)
                    await self.cleanup(setIdle: false)
                } else if error != nil, self.state == .finishing {
                    self.recognitionTask = nil
                    self.recognitionRequest = nil
                    await self.finishAndProcessTranscript()
                }
            }
        }
    }

    private func finishAndProcessTranscript() async {
        guard state == .finishing else { return }
        await cleanup()
        completedTranscriptGeneration += 1
    }

    private func cleanup(setIdle: Bool = true) async {
        await audioInput.stop()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        requestRelay.set(nil)
        speechRecognizer = nil
        audioLevel = 0
        activeGeneration = nil
        if let sessionGeneration {
            self.sessionGeneration = nil
            await AudioSessionCoordinator.shared.deactivate(if: sessionGeneration)
        }
        if setIdle { state = .idle }
    }

    private static func join(_ first: String, _ second: String) -> String {
        [first, second].filter { !$0.isEmpty }.joined(separator: first.isEmpty || second.isEmpty ? "" : " ")
    }

    private func requestSpeechAuthorization() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        if status != .notDetermined { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined: return await AVAudioApplication.requestRecordPermission()
        @unknown default: return false
        }
    }
}

private actor AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()
    private var activeGeneration: UUID?

    func activate() throws -> UUID {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let generation = UUID()
        activeGeneration = generation
        return generation
    }

    func deactivate(if generation: UUID) {
        guard activeGeneration == generation else { return }
        activeGeneration = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private actor AudioInputEngine {
    private let engine = AVAudioEngine()
    private var installedTap = false

    func start(
        relay: AudioRequestRelay,
        meter: AudioMeterGate,
        silenceDetector: AudioSilenceDetector,
        onMeter: @escaping @Sendable (Float) -> Void,
        onSilence: @escaping @Sendable () -> Void
    ) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechCaptureError.noMicrophoneRoute
        }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            guard buffer.frameLength > 0 else { return }
            relay.append(buffer)
            guard let data = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sum: Double = 0
            for index in 0..<frames {
                let sample = Double(data[index])
                sum += sample * sample
            }
            let rms = Float(sqrt(sum / Double(frames)))
            if meter.shouldPublish() { onMeter(min(1, rms * 12)) }
            if silenceDetector.didDetectSilence(rms: rms) { onSilence() }
        }
        installedTap = true
        engine.prepare()
        try engine.start()
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if installedTap {
            engine.inputNode.removeTap(onBus: 0)
            installedTap = false
        }
    }
}

private final class AudioRequestRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = request
        lock.unlock()
        current?.append(buffer)
    }
}

private final class AudioMeterGate: @unchecked Sendable {
    private let lock = NSLock()
    private let minimumInterval: TimeInterval
    private var lastPublish = Date.distantPast

    init(minimumInterval: TimeInterval) { self.minimumInterval = minimumInterval }

    func shouldPublish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(lastPublish) >= minimumInterval else { return false }
        lastPublish = now
        return true
    }
}

private final class AudioSilenceDetector: @unchecked Sendable {
    private let lock = NSLock()
    private let silenceDuration: TimeInterval = 2
    private let speechThreshold: Float = 0.008
    private var hasHeardSpeech = false
    private var lastSpeechTime: TimeInterval = 0
    private var didFire = false

    func reset() {
        lock.lock()
        hasHeardSpeech = false
        lastSpeechTime = 0
        didFire = false
        lock.unlock()
    }

    func didDetectSilence(rms: Float) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        if rms >= speechThreshold {
            hasHeardSpeech = true
            lastSpeechTime = now
            return false
        }
        guard hasHeardSpeech, !didFire, now - lastSpeechTime >= silenceDuration else { return false }
        didFire = true
        return true
    }
}

private enum SpeechCaptureError: LocalizedError {
    case noMicrophoneRoute
    var errorDescription: String? { "No usable microphone route is available." }
}
