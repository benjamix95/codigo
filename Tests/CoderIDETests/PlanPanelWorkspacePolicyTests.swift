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

    func testHistoryEntryCompatibilityAllowsSameContextAcrossDifferentConversation() {
        let contextId = UUID()
        let currentConversationId = UUID()
        let otherConversationId = UUID()
        let entry = PlanHistoryEntry(
            conversationId: otherConversationId,
            contextId: contextId,
            contextFolderPath: nil,
            title: "Plan",
            markdown: "## Plan: A\n## Todo\n- [ ] Step",
            options: [],
            chosenPath: nil
        )

        XCTAssertTrue(
            isPlanHistoryEntryCompatibleWithCurrentContext(
                entry: entry,
                currentConversationId: currentConversationId,
                currentContextId: contextId,
                currentContextFolderPath: nil
            )
        )
    }

    func testHistoryEntryCompatibilityRejectsDifferentContext() {
        let entry = PlanHistoryEntry(
            conversationId: UUID(),
            contextId: UUID(),
            contextFolderPath: "/tmp/other",
            title: "Plan",
            markdown: "## Plan: A\n## Todo\n- [ ] Step",
            options: [],
            chosenPath: nil
        )

        XCTAssertFalse(
            isPlanHistoryEntryCompatibleWithCurrentContext(
                entry: entry,
                currentConversationId: UUID(),
                currentContextId: UUID(),
                currentContextFolderPath: "/tmp/current"
            )
        )
    }
}
