import AVFoundation
import Foundation
import Speech

enum VoiceInputError: LocalizedError {
    case microphonePermissionDenied
    case speechPermissionDenied
    case missingPrivacyUsageDescription(String)
    case unsupportedExecutionContext
    case recognizerUnavailable
    case recognizerUnavailableForLocale(String)
    case audioEngineFailure(String)
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission denied. Enable it in macOS settings."
        case .speechPermissionDenied:
            return "Speech Recognition permission denied. Enable it in macOS settings."
        case .missingPrivacyUsageDescription(let key):
            return "Missing privacy configuration (\(key)) in app bundle. Launch as app bundle (e.g. `open Codigo.app`), not with `swift run`."
        case .unsupportedExecutionContext:
            return "Unsupported execution context for voice input."
        case .recognizerUnavailable:
            return "Speech recognizer not available on this device."
        case .recognizerUnavailableForLocale(let locale):
            return "Speech recognizer not available for locale \(locale)."
        case .audioEngineFailure(let message):
            return "Audio error: \(message)"
        case .noSpeechDetected:
            return "No speech detected. Try again closer to the microphone."
        }
    }
}

@MainActor
protocol VoiceInputBackend: AnyObject {
    var onTranscript: ((String, Bool) -> Void)? { get set }
    var onFailure: ((Error) -> Void)? { get set }

    func requestPermissions() async throws
    func start(locale: Locale) throws
    func stop()
    func cancel()
}

@MainActor
final class VoiceInputController: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case transcribing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript: String = ""

    private let backend: any VoiceInputBackend
    private let localeProvider: () -> Locale
    private var onFinalTranscription: ((String) -> Void)?

    init(
        backend: (any VoiceInputBackend)? = nil,
        localeProvider: @escaping () -> Locale = { Locale.autoupdatingCurrent }
    ) {
        self.backend = backend ?? SpeechVoiceInputBackend()
        self.localeProvider = localeProvider
        attachBackendCallbacks()
    }

    func start(onFinalTranscription: @escaping (String) -> Void) {
        guard canStart else { return }
        self.onFinalTranscription = onFinalTranscription
        transcript = ""
        state = .requestingPermission

        Task { @MainActor in
            do {
                try await backend.requestPermissions()
                try backend.start(locale: localeProvider())
                state = .listening
            } catch {
                state = .failed(Self.message(for: error))
            }
        }
    }

    func stop() {
        guard state == .listening else { return }
        state = .transcribing
        backend.stop()
    }

    func cancel() {
        backend.cancel()
        transcript = ""
        onFinalTranscription = nil
        state = .idle
    }

    private var canStart: Bool {
        switch state {
        case .idle, .failed:
            return true
        case .requestingPermission, .listening, .transcribing:
            return false
        }
    }

    private func attachBackendCallbacks() {
        backend.onTranscript = { [weak self] text, isFinal in
            guard let self else { return }
            Task { @MainActor in
                self.transcript = text
                if isFinal {
                    self.finalizeTranscription(text)
                }
            }
        }

        backend.onFailure = { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                self.state = .failed(Self.message(for: error))
                self.backend.cancel()
            }
        }
    }

    private func finalizeTranscription(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        backend.cancel()
        defer {
            transcript = ""
            onFinalTranscription = nil
            state = .idle
        }

        guard !normalized.isEmpty else {
            state = .failed(Self.message(for: VoiceInputError.noSpeechDetected))
            return
        }
        onFinalTranscription?(normalized)
    }

    private static func message(for error: Error) -> String {
        if let voiceError = error as? VoiceInputError,
           let message = voiceError.errorDescription {
            return message
        }
        let localized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return localized.isEmpty ? "Unexpected voice error." : localized
    }
}

@MainActor
final class SpeechVoiceInputBackend: NSObject, VoiceInputBackend {
    var onTranscript: ((String, Bool) -> Void)?
    var onFailure: ((Error) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let privacyKeys = [
        "NSMicrophoneUsageDescription",
        "NSSpeechRecognitionUsageDescription"
    ]

    func requestPermissions() async throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            throw VoiceInputError.unsupportedExecutionContext
        }
        try validatePrivacyUsageDescriptions()

        let micGranted = await requestMicrophonePermission()
        guard micGranted else { throw VoiceInputError.microphonePermissionDenied }

        let speechStatus = await requestSpeechPermission()
        guard speechStatus == .authorized else {
            throw VoiceInputError.speechPermissionDenied
        }
    }

    func start(locale: Locale) throws {
        cancel()

        let fallbackLocale = Locale(identifier: "en-US")
        guard let recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: fallbackLocale)
        else {
            throw VoiceInputError.recognizerUnavailable
        }
        guard recognizer.isAvailable else {
            throw VoiceInputError.recognizerUnavailableForLocale(locale.identifier)
        }

        let engine = AVAudioEngine()
        audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.onTranscript?(result.bestTranscription.formattedString, result.isFinal)
            }
            if let error {
                self.onFailure?(error)
            }
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            cancel()
            throw VoiceInputError.audioEngineFailure(error.localizedDescription)
        }
    }

    func stop() {
        guard let engine = audioEngine else { return }
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }

    func cancel() {
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func requestSpeechPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                continuation.resume(returning: authStatus)
            }
        }
    }

    private func validatePrivacyUsageDescriptions() throws {
        for key in privacyKeys {
            guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw VoiceInputError.missingPrivacyUsageDescription(key)
            }
        }
    }
}
