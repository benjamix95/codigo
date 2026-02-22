import Foundation
import XCTest
@testable import CoderIDE

@MainActor
final class VoiceInputControllerTests: XCTestCase {
    func testStartFailsWhenPermissionDenied() async {
        let backend = MockVoiceInputBackend()
        backend.permissionError = VoiceInputError.microphonePermissionDenied
        let controller = VoiceInputController(backend: backend)

        controller.start { _ in
            XCTFail("Non dovrebbe arrivare trascrizione finale")
        }
        await tick()

        guard case .failed(let message) = controller.state else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(message.lowercased().contains("microfono"))
    }

    func testSuccessfulTranscriptionFlowInsertsFinalText() async {
        let backend = MockVoiceInputBackend()
        let expectedLocale = Locale(identifier: "it-IT")
        let controller = VoiceInputController(
            backend: backend,
            localeProvider: { expectedLocale }
        )
        var finalText = ""

        controller.start { text in
            finalText = text
        }
        await tick()

        XCTAssertEqual(controller.state, .listening)
        XCTAssertEqual(backend.startedLocale?.identifier, expectedLocale.identifier)

        backend.emitTranscript("ciao", isFinal: false)
        await tick()
        XCTAssertEqual(controller.transcript, "ciao")

        controller.stop()
        XCTAssertEqual(controller.state, .transcribing)

        backend.emitTranscript("ciao mondo", isFinal: true)
        await tick()

        XCTAssertEqual(finalText, "ciao mondo")
        XCTAssertEqual(controller.state, .idle)
    }

    func testRuntimeRecognitionErrorMovesControllerToFailed() async {
        let backend = MockVoiceInputBackend()
        let controller = VoiceInputController(backend: backend)

        controller.start { _ in }
        await tick()
        XCTAssertEqual(controller.state, .listening)

        backend.emitFailure(VoiceInputError.recognizerUnavailable)
        await tick()

        guard case .failed(let message) = controller.state else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(message.lowercased().contains("recognizer"))
    }

    private func tick() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
}

@MainActor
private final class MockVoiceInputBackend: VoiceInputBackend {
    var onTranscript: ((String, Bool) -> Void)?
    var onFailure: ((Error) -> Void)?

    var permissionError: Error?
    var startError: Error?
    var startedLocale: Locale?

    func requestPermissions() async throws {
        if let permissionError {
            throw permissionError
        }
    }

    func start(locale: Locale) throws {
        if let startError {
            throw startError
        }
        startedLocale = locale
    }

    func stop() {}
    func cancel() {}

    func emitTranscript(_ text: String, isFinal: Bool) {
        onTranscript?(text, isFinal)
    }

    func emitFailure(_ error: Error) {
        onFailure?(error)
    }
}
