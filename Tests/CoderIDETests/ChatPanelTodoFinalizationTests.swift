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
            todos: [inProgress, pendingReview, done]
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
}
