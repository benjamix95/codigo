import XCTest
@testable import CoderIDE

@MainActor
final class DebugStoreGateAndFindingsTests: XCTestCase {

    // MARK: - Gate Flags

    func testStartDebugSessionResetsGateFlags() {
        let store = DebugStore()
        store.isAwaitingUserClarification = true
        store.isAwaitingReproduceConfirmation = true
        store.isAwaitingFixConfirmation = true
        store.skippedQuestionsWarning = true
        store.debugFindings = [DebugFinding(title: "old")]

        store.startDebugSession(errorContext: "new context")

        XCTAssertFalse(store.isAwaitingUserClarification)
        XCTAssertFalse(store.isAwaitingReproduceConfirmation)
        XCTAssertFalse(store.isAwaitingFixConfirmation)
        XCTAssertFalse(store.skippedQuestionsWarning)
        XCTAssertTrue(store.debugFindings.isEmpty)
    }

    func testResetSessionResetsGateFlags() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "boom")
        store.isAwaitingUserClarification = true
        store.isAwaitingReproduceConfirmation = true
        store.isAwaitingFixConfirmation = true
        store.skippedQuestionsWarning = true

        store.resetSession()

        XCTAssertFalse(store.isAwaitingUserClarification)
        XCTAssertFalse(store.isAwaitingReproduceConfirmation)
        XCTAssertFalse(store.isAwaitingFixConfirmation)
        XCTAssertFalse(store.skippedQuestionsWarning)
    }

    // MARK: - setPhase returns Bool

    func testSetPhaseReturnsTrueForValidTransition() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "test")
        let result = store.setPhase(.reproducing)
        XCTAssertTrue(result)
        XCTAssertEqual(store.phase, .reproducing)
    }

    func testSetPhaseReturnsFalseForInvalidTransition() {
        let store = DebugStore()
        // idle → verifying is invalid
        let result = store.setPhase(.verifying)
        XCTAssertFalse(result)
        XCTAssertEqual(store.phase, .idle)
    }

    func testSetPhaseReturnsTrueForSamePhase() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "test")
        store.setPhase(.reproducing)
        let result = store.setPhase(.reproducing)
        XCTAssertTrue(result)
    }

    // MARK: - Findings

    func testAddFindingFromHypothesis() {
        let store = DebugStore()
        let hypothesis = DebugHypothesis(
            title: "Memory leak in NetworkManager",
            description: "Retain cycle in closure",
            status: .confirmed,
            evidence: ["ARC analysis shows cycle"]
        )

        store.addFinding(fromHypothesis: hypothesis)

        XCTAssertEqual(store.debugFindings.count, 1)
        XCTAssertEqual(store.debugFindings.first?.title, "Memory leak in NetworkManager")
        XCTAssertEqual(store.debugFindings.first?.severity, .high)
        XCTAssertEqual(store.debugFindings.first?.status, .investigating)
    }

    func testAddFindingFromMarker() {
        let store = DebugStore()
        let marker = DebugMarker(
            filePath: "Sources/App.swift",
            lineNumber: 42,
            markerComment: "Potential null dereference"
        )

        store.addFinding(fromMarker: marker)

        XCTAssertEqual(store.debugFindings.count, 1)
        XCTAssertEqual(store.debugFindings.first?.filePath, "Sources/App.swift")
        XCTAssertEqual(store.debugFindings.first?.lineNumber, 42)
        XCTAssertEqual(store.debugFindings.first?.status, .open)
    }

    func testAddResolutionSummaryFinding() {
        let store = DebugStore()
        store.addResolutionSummaryFinding(summary: "Fixed memory leak by breaking retain cycle")

        XCTAssertEqual(store.debugFindings.count, 1)
        XCTAssertEqual(store.debugFindings.first?.severity, .info)
        XCTAssertEqual(store.debugFindings.first?.status, .fixed)
    }

    func testOpenFindingsCount() {
        let store = DebugStore()
        store.debugFindings = [
            DebugFinding(title: "A", status: .open),
            DebugFinding(title: "B", status: .investigating),
            DebugFinding(title: "C", status: .fixed),
            DebugFinding(title: "D", status: .dismissed),
        ]

        XCTAssertEqual(store.openFindingsCount, 2)
    }

    func testUpdateFindingStatus() {
        let store = DebugStore()
        let finding = DebugFinding(title: "Test finding", status: .open)
        store.debugFindings = [finding]

        let updated = store.updateFindingStatus(id: finding.id, status: .fixed)
        XCTAssertTrue(updated)
        XCTAssertEqual(store.debugFindings.first?.status, .fixed)
    }

    func testUpdateFindingStatusReturnsFalseForUnknownId() {
        let store = DebugStore()
        let result = store.updateFindingStatus(id: UUID(), status: .fixed)
        XCTAssertFalse(result)
    }
}
