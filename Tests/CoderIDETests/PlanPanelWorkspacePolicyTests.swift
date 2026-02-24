import XCTest
@testable import CoderIDE

final class PlanPanelWorkspacePolicyTests: XCTestCase {
    func testHasPlanContextFalseWhenCompletelyIdle() {
        XCTAssertFalse(
            hasPlanContext(
                phase: .idle,
                planningState: .idle,
                hasPlanBoard: false,
                hasSelectedHistoryEntry: false
            )
        )
    }

    func testHasPlanContextTrueForActivePhase() {
        XCTAssertTrue(
            hasPlanContext(
                phase: .analyzing,
                planningState: .idle,
                hasPlanBoard: false,
                hasSelectedHistoryEntry: false
            )
        )
    }

    func testHasPlanContextTrueForAwaitingClarification() {
        XCTAssertTrue(
            hasPlanContext(
                phase: .idle,
                planningState: .awaitingClarification(questions: "## Questions\n1. A?"),
                hasPlanBoard: false,
                hasSelectedHistoryEntry: false
            )
        )
    }

    func testHasPlanContextTrueForBoardOrHistorySelection() {
        XCTAssertTrue(
            hasPlanContext(
                phase: .idle,
                planningState: .idle,
                hasPlanBoard: true,
                hasSelectedHistoryEntry: false
            )
        )
        XCTAssertTrue(
            hasPlanContext(
                phase: .idle,
                planningState: .idle,
                hasPlanBoard: false,
                hasSelectedHistoryEntry: true
            )
        )
    }

    func testShouldMirrorAssistantContentFollowsPlanContext() {
        XCTAssertFalse(shouldMirrorAssistantContentInPlanWorkspace(hasPlanContext: false))
        XCTAssertTrue(shouldMirrorAssistantContentInPlanWorkspace(hasPlanContext: true))
    }
}
