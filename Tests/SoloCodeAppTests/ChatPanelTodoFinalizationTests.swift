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

    func testToolTraceTurnOutcomeMapsPipelineCompletionState() {
        XCTAssertEqual(
            toolTraceTurnOutcome(
                pipelineSuccess: true,
                pipelineWasCancelled: false
            ),
            .success
        )
        XCTAssertEqual(
            toolTraceTurnOutcome(
                pipelineSuccess: false,
                pipelineWasCancelled: true
            ),
            .aborted
        )
        XCTAssertEqual(
            toolTraceTurnOutcome(
                pipelineSuccess: false,
                pipelineWasCancelled: false
            ),
            .failed
        )
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

    func testSubagentBatchAutoCompletionPrefersInProgressTodoBeforePendingReviewTodo() {
        let inProgress = TodoItem(id: UUID(), title: "Implement fix", status: .inProgress, source: .agent)
        let pendingReview = TodoItem(id: UUID(), title: "Code Review & Test", status: .pending, source: .agent)
        let done = TodoItem(id: UUID(), title: "Done item", status: .done, source: .agent)

        let ids = todoIDsToAutoCompleteAfterSubagentBatch(
            todos: [inProgress, pendingReview, done],
            includePendingReviewTodo: true
        )

        XCTAssertEqual(ids, [inProgress.id])
        XCTAssertFalse(ids.contains(pendingReview.id))
        XCTAssertFalse(ids.contains(done.id))
    }

    func testSubagentBatchAutoCompletionCanExcludeCanonicalTodos() {
        let canonicalInProgress = TodoItem(
            id: UUID(),
            title: "Canonical plan step",
            status: .inProgress,
            source: .agent,
            isPlanCanonical: true
        )
        let runtimeInProgress = TodoItem(
            id: UUID(),
            title: "Runtime task",
            status: .inProgress,
            source: .agent,
            isPlanCanonical: false
        )

        let ids = todoIDsToAutoCompleteAfterSubagentBatch(
            todos: [canonicalInProgress, runtimeInProgress],
            includePendingReviewTodo: false,
            excludeCanonicalTodos: true
        )

        XCTAssertFalse(ids.contains(canonicalInProgress.id))
        XCTAssertTrue(ids.contains(runtimeInProgress.id))
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

    func testSubagentBatchAutoCompletionCompletesPendingReviewOnlyWhenExecutableWorkIsAlreadyDone() {
        let pendingReview = TodoItem(id: UUID(), title: "Code Review & Test", status: .pending, source: .agent)
        let pendingDoc = TodoItem(id: UUID(), title: "Doc Writer", status: .pending, source: .agent)

        let ids = todoIDsToAutoCompleteAfterSubagentBatch(
            todos: [pendingReview, pendingDoc],
            includePendingReviewTodo: true
        )

        XCTAssertEqual(ids, [pendingReview.id])
        XCTAssertFalse(ids.contains(pendingDoc.id))
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
        XCTAssertFalse(ids.contains(reviewA.id))
        XCTAssertFalse(ids.contains(inProgressB.id))
    }

    func testSubagentBatchAutoCompletionIgnoresManualInProgressTodos() {
        let manualInProgress = TodoItem(
            id: UUID(),
            title: "Manual checklist",
            status: .inProgress,
            source: .manual
        )
        let agentInProgress = TodoItem(
            id: UUID(),
            title: "Agent task",
            status: .inProgress,
            source: .agent
        )

        let ids = todoIDsToAutoCompleteAfterSubagentBatch(
            todos: [manualInProgress, agentInProgress]
        )

        XCTAssertFalse(ids.contains(manualInProgress.id))
        XCTAssertTrue(ids.contains(agentInProgress.id))
    }

    func testSubagentBatchAutoCompletionIgnoresOperationalPlaceholders() {
        let runtimePlaceholder = TodoItem(
            id: UUID(),
            title: "Runtime placeholder",
            status: .inProgress,
            source: .agent,
            isOperationalPlaceholder: true
        )
        let realAgentTodo = TodoItem(
            id: UUID(),
            title: "Agent task",
            status: .inProgress,
            source: .agent
        )
        let reviewTodo = TodoItem(
            id: UUID(),
            title: "Code Review & Test",
            status: .pending,
            source: .agent,
            isOperationalPlaceholder: true
        )

        let ids = todoIDsToAutoCompleteAfterSubagentBatch(
            todos: [runtimePlaceholder, realAgentTodo, reviewTodo],
            includePendingReviewTodo: true
        )

        XCTAssertFalse(ids.contains(runtimePlaceholder.id))
        XCTAssertTrue(ids.contains(realAgentTodo.id))
        XCTAssertFalse(ids.contains(reviewTodo.id))
    }

    func testTraceEventsContainSuccessfulCodeEditsIgnoresReadBatchEvents() {
        let readEvent = makeToolTraceEvent(
            type: "read_batch_completed",
            payload: [
                "status": "completed",
                "path": "/tmp/workspace/Sources/Feature/ReadOnly.swift",
            ],
            phase: .editing,
            isRunning: false
        )

        XCTAssertFalse(traceEventsContainSuccessfulCodeEdits([readEvent]))
    }

    func testTouchedFilePathsFromTraceEventsIncludesOnlySuccessfulFileMutations() {
        let successfulMutation = makeToolTraceEvent(
            type: "file_change",
            payload: [
                "status": "completed",
                "file_path": "/tmp/workspace/Sources/Feature/Updated.swift",
            ],
            phase: .editing,
            isRunning: false
        )
        let readOnlyEvent = makeToolTraceEvent(
            type: "read_batch_completed",
            payload: [
                "status": "completed",
                "path": "/tmp/workspace/Sources/Feature/ReadOnly.swift",
            ],
            phase: .editing,
            isRunning: false
        )
        let failedMutation = makeToolTraceEvent(
            type: "file_change",
            payload: [
                "status": "failed",
                "path": "/tmp/workspace/Sources/Feature/Failed.swift",
            ],
            phase: .editing,
            isRunning: false
        )

        let files = touchedFilePathsFromTraceEvents([successfulMutation, readOnlyEvent, failedMutation])
        XCTAssertEqual(files, ["Sources/Feature/Updated.swift"])
    }

    private func makeToolTraceEvent(
        type: String,
        payload: [String: String],
        phase: ActivityPhase = .editing,
        isRunning: Bool = false
    ) -> ToolTraceEvent {
        ToolTraceEvent(
            sequence: 1,
            timestamp: .now,
            providerId: "test-provider",
            conversationId: UUID(),
            assistantMessageId: UUID(),
            type: type,
            title: "Test event",
            detail: nil,
            payload: payload,
            phase: phase,
            isRunning: isRunning,
            groupId: nil,
            rawKind: "generic"
        )
    }
}
