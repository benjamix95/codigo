import XCTest
@testable import CoderIDE

@MainActor
final class SwarmProgressStoreTests: XCTestCase {
    func testMarkStartedCompletesImmediatePredecessorOnly() {
        let store = SwarmProgressStore()
        store.setSteps(["Explorer", "Coder", "Reviewer"])

        store.markStarted(name: "Explorer")
        store.markStarted(name: "Coder")

        XCTAssertEqual(store.steps[0].status, .completed)
        XCTAssertEqual(store.steps[1].status, .inProgress)
        XCTAssertEqual(store.steps[2].status, .pending)
    }

    func testMarkStartedDoesNotForceUnrelatedParallelStepToComplete() {
        let store = SwarmProgressStore()
        store.setSteps(["Explorer", "Coder", "Reviewer"])

        store.markStarted(name: "Explorer")
        store.markStarted(name: "Reviewer")

        // Coder was never started, so Explorer should remain in progress.
        XCTAssertEqual(store.steps[0].status, .inProgress)
        XCTAssertEqual(store.steps[1].status, .pending)
        XCTAssertEqual(store.steps[2].status, .inProgress)
    }
}
