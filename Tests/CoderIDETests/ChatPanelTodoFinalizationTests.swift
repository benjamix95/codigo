import XCTest
@testable import CoderIDE

final class ChatPanelTodoFinalizationTests: XCTestCase {
    func testAutoTodoFinalStatusIsDoneOnlyOnSuccess() {
        XCTAssertEqual(autoTodoFinalStatus(for: .success), .done)
        XCTAssertEqual(autoTodoFinalStatus(for: .failed), .blocked)
        XCTAssertEqual(autoTodoFinalStatus(for: .aborted), .blocked)
    }

    func testToolTraceTurnOutcomeMapsFlowCoordinatorState() {
        XCTAssertEqual(toolTraceTurnOutcome(for: .idle), .success)
        XCTAssertEqual(toolTraceTurnOutcome(for: .streaming), .success)
        XCTAssertEqual(toolTraceTurnOutcome(for: .completed), .success)
        XCTAssertEqual(toolTraceTurnOutcome(for: .error), .failed)
        XCTAssertEqual(toolTraceTurnOutcome(for: .interrupted), .aborted)
    }

    func testRolloverAutoTodoOutcomeBlocksInterruptedOrRunningTurns() {
        XCTAssertEqual(
            rolloverAutoTodoOutcome(for: .interrupted, hasRunningOperations: true),
            .aborted
        )
        XCTAssertEqual(
            rolloverAutoTodoOutcome(for: .error, hasRunningOperations: false),
            .failed
        )
        XCTAssertEqual(
            rolloverAutoTodoOutcome(for: .streaming, hasRunningOperations: true),
            .aborted
        )
        XCTAssertEqual(
            rolloverAutoTodoOutcome(for: .completed, hasRunningOperations: true),
            .aborted
        )
        XCTAssertEqual(
            rolloverAutoTodoOutcome(for: .completed, hasRunningOperations: false),
            .success
        )
    }

    func testSubagentBatchAutoCompletionIncludesInProgressAndPendingReviewTodo() {
        let inProgress = TodoItem(id: UUID(), title: "Implement fix", status: .inProgress, source: .agent)
        let pendingReview = TodoItem(id: UUID(), title: "Code Review & Test", status: .pending, source: .agent)
        let done = TodoItem(id: UUID(), title: "Done item", status: .done, source: .agent)

        let ids = todoIDsToAutoCompleteAfterSubagentBatch(
            todos: [inProgress, pendingReview, done],
            includePendingReviewTodo: true
        )

        XCTAssertTrue(ids.contains(inProgress.id))
        XCTAssertTrue(ids.contains(pendingReview.id))
        XCTAssertFalse(ids.contains(done.id))
    }

    func testSubagentBatchAutoCompletionExcludesGenericPendingTodos() {
        let pendingGeneric = TodoItem(id: UUID(), title: "Write docs", status: .pending, source: .agent)
        let ids = todoIDsToAutoCompleteAfterSubagentBatch(todos: [pendingGeneric])
        XCTAssertFalse(ids.contains(pendingGeneric.id))
    }

    func testSubagentBatchAutoCompletionExcludesPendingReviewWhenNotRequested() {
        let pendingReview = TodoItem(id: UUID(), title: "Code Review & Test", status: .pending, source: .agent)
        let ids = todoIDsToAutoCompleteAfterSubagentBatch(
            todos: [pendingReview],
            includePendingReviewTodo: false
        )
        XCTAssertFalse(ids.contains(pendingReview.id))
    }

    func testShouldAutoCompletePendingReviewTodoRequiresReviewerAndTestWriter() {
        XCTAssertTrue(shouldAutoCompletePendingReviewTodo(subagentBatchPayload: [
            "roles": "reviewer,testWriter",
        ]))
        XCTAssertTrue(shouldAutoCompletePendingReviewTodo(subagentBatchPayload: [
            "roles": "testwriter,reviewer",
        ]))
        XCTAssertFalse(shouldAutoCompletePendingReviewTodo(subagentBatchPayload: [
            "roles": "reviewer",
        ]))
        XCTAssertFalse(shouldAutoCompletePendingReviewTodo(subagentBatchPayload: [
            "roles": "explorer,coder",
        ]))
    }

    func testSubagentBatchAutoCompletionRespectsConversationScope() {
        let conversationA = UUID()
        let conversationB = UUID()
        let inProgressA = TodoItem(
            id: UUID(),
            title: "Implement A",
            status: .inProgress,
            source: .agent,
            planConversationId: conversationA
        )
        let reviewA = TodoItem(
            id: UUID(),
            title: "Code Review & Test",
            status: .pending,
            source: .agent,
            planConversationId: conversationA
        )
        let inProgressB = TodoItem(
            id: UUID(),
            title: "Implement B",
            status: .inProgress,
            source: .agent,
            planConversationId: conversationB
        )

        let ids = todoIDsToAutoCompleteAfterSubagentBatch(
            todos: [inProgressA, reviewA, inProgressB],
            conversationId: conversationA,
            includePendingReviewTodo: true
        )

        XCTAssertTrue(ids.contains(inProgressA.id))
        XCTAssertTrue(ids.contains(reviewA.id))
        XCTAssertFalse(ids.contains(inProgressB.id))
    }
}
