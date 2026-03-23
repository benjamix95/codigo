import XCTest
@testable import CoderIDE

final class ChatTodoVisibilityTests: XCTestCase {
    func testLiveTodoCardRemainsVisibleDuringPipelineProgress() {
        XCTAssertTrue(
            shouldShowLiveTodoCardInChat(
                hasSwarmSteps: false,
                hasLiveSwarmCards: false,
                hasPipelineProgress: true
            )
        )
    }

    func testLiveTodoCardIsHiddenWhenSwarmAlreadyOwnsProgressUI() {
        XCTAssertFalse(
            shouldShowLiveTodoCardInChat(
                hasSwarmSteps: true,
                hasLiveSwarmCards: false,
                hasPipelineProgress: false
            )
        )
        XCTAssertFalse(
            shouldShowLiveTodoCardInChat(
                hasSwarmSteps: false,
                hasLiveSwarmCards: true,
                hasPipelineProgress: false
            )
        )
    }

    func testTodoCardPrefersAssistantMessageWithTraceOverNewerAssistantStub() {
        let tracedAssistantId = UUID()
        let newerAssistantId = UUID()

        let resolved = resolveTodoCardAssistantMessageId(
            messages: [
                ChatMessage(id: tracedAssistantId, role: .assistant, content: "Main reply"),
                ChatMessage(id: newerAssistantId, role: .assistant, content: ""),
            ],
            activeAssistantMessageId: nil,
            latestAssistantMessageIdWithTrace: tracedAssistantId,
            pipelineAssistantMessageId: newerAssistantId,
            latestVisibleAssistantMessageId: newerAssistantId
        )

        XCTAssertEqual(resolved, tracedAssistantId)
    }

    func testTodoCardPrefersActiveAssistantMessageWhenPresent() {
        let activeAssistantId = UUID()
        let tracedAssistantId = UUID()

        let resolved = resolveTodoCardAssistantMessageId(
            messages: [
                ChatMessage(id: tracedAssistantId, role: .assistant, content: "Older reply"),
                ChatMessage(id: activeAssistantId, role: .assistant, content: ""),
            ],
            activeAssistantMessageId: activeAssistantId,
            latestAssistantMessageIdWithTrace: tracedAssistantId,
            pipelineAssistantMessageId: tracedAssistantId,
            latestVisibleAssistantMessageId: tracedAssistantId
        )

        XCTAssertEqual(resolved, activeAssistantId)
    }

    func testTodoCardFallsBackToLatestVisibleAssistantWhenPipelineTargetIsMissing() {
        let olderAssistantId = UUID()
        let latestAssistantId = UUID()

        let resolved = resolveTodoCardAssistantMessageId(
            messages: [
                ChatMessage(id: olderAssistantId, role: .assistant, content: "Older reply"),
                ChatMessage(id: latestAssistantId, role: .assistant, content: "Latest reply"),
            ],
            activeAssistantMessageId: nil,
            latestAssistantMessageIdWithTrace: nil,
            pipelineAssistantMessageId: nil,
            latestVisibleAssistantMessageId: latestAssistantId
        )

        XCTAssertEqual(resolved, latestAssistantId)
    }

    func testChatTimelineInvalidatesImmediatelyForTodoAndPlanMutations() {
        XCTAssertTrue(shouldInvalidateChatTimelineForLiveMutation(eventType: "todo_write"))
        XCTAssertTrue(shouldInvalidateChatTimelineForLiveMutation(eventType: "plan_create"))
        XCTAssertTrue(shouldInvalidateChatTimelineForLiveMutation(eventType: "plan_step_upsert"))
    }

    func testChatTimelineDoesNotInvalidateForUnrelatedEvents() {
        XCTAssertFalse(shouldInvalidateChatTimelineForLiveMutation(eventType: "policy_ack"))
        XCTAssertFalse(shouldInvalidateChatTimelineForLiveMutation(eventType: "usage"))
        XCTAssertFalse(shouldInvalidateChatTimelineForLiveMutation(eventType: "command_execution"))
    }

    func testTodoPlanStartPolicyRequiresTodoBeforeOtherOperationalEvents() {
        let violation = todoPlanStartPolicyViolation(
            state: ToolStartRequirementsState(),
            type: "mcp_tool_call",
            payload: ["mcp_tool": "coderide_read"]
        )

        XCTAssertEqual(violation?.errorCode, "todo_first_required")
    }

    func testTodoPlanStartPolicyRequiresPlanAfterTodo() {
        let violation = todoPlanStartPolicyViolation(
            state: ToolStartRequirementsState(didSeeTodoWrite: true, didSeePlanLifecycle: false),
            type: "command_execution",
            payload: ["command": "rg TODO ."]
        )

        XCTAssertEqual(violation?.errorCode, "plan_after_todo_required")
    }

    func testTodoPlanStartPolicyAllowsPlanLifecycleAfterTodo() {
        let violation = todoPlanStartPolicyViolation(
            state: ToolStartRequirementsState(didSeeTodoWrite: true, didSeePlanLifecycle: false),
            type: "plan_create",
            payload: [:]
        )

        XCTAssertNil(violation)
    }

    func testLinearChatHidesTodoEventsWhenTodoCardIsVisible() {
        XCTAssertFalse(
            shouldShowOperationEventInLinearChat(
                eventType: "todo_write",
                payload: [:],
                showTodoCard: true
            )
        )
        XCTAssertFalse(
            shouldShowOperationEventInLinearChat(
                eventType: "mcp_tool_call",
                payload: ["mcp_tool": "coderide_todo_write"],
                showTodoCard: true
            )
        )
    }

    func testLinearChatHidesPolicyAckButKeepsOperationalEvents() {
        XCTAssertFalse(
            shouldShowOperationEventInLinearChat(
                eventType: "policy_ack",
                payload: [:],
                showTodoCard: false
            )
        )
        XCTAssertTrue(
            shouldShowOperationEventInLinearChat(
                eventType: "command_execution",
                payload: ["command": "rg Chat ."],
                showTodoCard: false
            )
        )
    }
}
