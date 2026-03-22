import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class DebugProjectionEventConsumerGateTests: XCTestCase {

    // MARK: - Gate Flags from debugUserRequest

    func testReproduceRequestSetsAwaitingReproduceConfirmation() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "crash")

        let event = NormalizedEvent.debugUserRequest(kind: "reproduce", prompt: "Steps to reproduce the crash")
        let effects = DebugProjectionEventConsumer.apply(event, to: store)

        XCTAssertTrue(store.isAwaitingReproduceConfirmation)
        XCTAssertEqual(store.clarificationQuestions, "Steps to reproduce the crash")
        XCTAssertEqual(store.phase, .reproducing)
        XCTAssertTrue(effects.shouldEnableDebugMode)
        XCTAssertTrue(effects.shouldRevealDebugPanel)
    }

    func testFixConfirmationRequestSetsAwaitingFixConfirmation() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "bug")
        store.phase = .verifying

        let event = NormalizedEvent.debugUserRequest(kind: "fix_confirmation", prompt: "Verify the fix works")
        _ = DebugProjectionEventConsumer.apply(event, to: store)

        XCTAssertTrue(store.isAwaitingFixConfirmation)
        XCTAssertEqual(store.clarificationQuestions, "Verify the fix works")
    }

    func testGenericQuestionSetsAwaitingUserClarification() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "bug")

        let event = NormalizedEvent.debugUserRequest(kind: "question", prompt: "What OS version?")
        _ = DebugProjectionEventConsumer.apply(event, to: store)

        XCTAssertTrue(store.isAwaitingUserClarification)
        XCTAssertEqual(store.clarificationQuestions, "What OS version?")
    }

    func testEmptyPromptIsIgnored() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "bug")

        let event = NormalizedEvent.debugUserRequest(kind: "question", prompt: "   ")
        _ = DebugProjectionEventConsumer.apply(event, to: store)

        XCTAssertFalse(store.isAwaitingUserClarification)
        XCTAssertTrue(store.clarificationQuestions.isEmpty)
    }

    // MARK: - Skipped Questions Warning

    func testSkippedQuestionsWarningWhenJumpingToFixWithoutHypotheses() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "crash")
        store.setPhase(.reproducing)

        let event = NormalizedEvent.debugPhaseUpdate(phase: .fixing, detail: "Applying fix")
        _ = DebugProjectionEventConsumer.apply(event, to: store)

        XCTAssertTrue(store.skippedQuestionsWarning)
        XCTAssertTrue(store.logs.contains { $0.message.contains("without asking questions") })
    }

    func testNoWarningWhenHypothesesExistBeforeFix() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "crash")
        store.setPhase(.reproducing)
        _ = store.addHypothesis(title: "Memory leak", description: "In closure")

        let event = NormalizedEvent.debugPhaseUpdate(phase: .fixing, detail: "Applying fix")
        _ = DebugProjectionEventConsumer.apply(event, to: store)

        XCTAssertFalse(store.skippedQuestionsWarning)
    }

    // MARK: - Findings from Events

    func testConfirmedHypothesisCreatesFinding() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "bug")
        let hypothesisId = store.addHypothesis(
            title: "Null pointer",
            description: "in AppDelegate",
            status: .investigating
        )

        let payload = DebugHypothesizeToolPayload(
            action: "update",
            hypothesisId: hypothesisId,
            hypothesisIdRaw: hypothesisId.uuidString,
            title: nil,
            description: nil,
            status: .confirmed,
            evidence: "Stack trace confirms"
        )
        let event = NormalizedEvent.debugHypothesize(payload)
        _ = DebugProjectionEventConsumer.apply(event, to: store)

        XCTAssertEqual(store.debugFindings.count, 1)
        XCTAssertEqual(store.debugFindings.first?.title, "Null pointer")
        XCTAssertEqual(store.debugFindings.first?.status, .investigating)
    }

    func testDebugMarkCreatesMarkerFinding() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "bug")
        store.setPhase(.fixing)

        let payload = DebugMarkToolPayload(
            filePath: "Sources/App.swift",
            lineNumber: 42,
            comment: "Check nil dereference",
            originalContent: nil
        )
        let event = NormalizedEvent.debugMark(payload)
        _ = DebugProjectionEventConsumer.apply(event, to: store)

        XCTAssertEqual(store.debugFindings.count, 1)
        XCTAssertEqual(store.debugFindings.first?.filePath, "Sources/App.swift")
        XCTAssertEqual(store.debugFindings.first?.lineNumber, 42)
    }

    func testResolvedSessionCreatesResolutionFinding() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "bug")
        store.setPhase(.verifying)

        let event = NormalizedEvent.debugResolved(summary: "Fixed null pointer in AppDelegate")
        _ = DebugProjectionEventConsumer.apply(event, to: store)

        XCTAssertTrue(store.debugFindings.contains { $0.title.contains("Resolved:") })
        XCTAssertEqual(store.debugFindings.last?.status, .fixed)
    }

    // MARK: - Phase Transition Clears Questions

    func testPhaseTransitionToFixingClearsClarificationQuestions() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "bug")
        store.setPhase(.reproducing)
        store.clarificationQuestions = "Previous question"

        let event = NormalizedEvent.debugPhaseUpdate(phase: .fixing, detail: nil)
        _ = DebugProjectionEventConsumer.apply(event, to: store)

        XCTAssertTrue(store.clarificationQuestions.isEmpty)
    }
}
