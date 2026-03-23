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
        XCTAssertTrue(
            shouldShowLiveTodoCardInChat(
                hasSwarmSteps: true,
                hasLiveSwarmCards: false,
                hasPipelineProgress: false
            )
        )
        XCTAssertTrue(
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
                ChatMessage(id: activeAssistantId, role: .assistant, content: "Current reply"),
            ],
            activeAssistantMessageId: activeAssistantId,
            latestAssistantMessageIdWithTrace: tracedAssistantId,
            pipelineAssistantMessageId: tracedAssistantId,
            latestVisibleAssistantMessageId: tracedAssistantId
        )

        XCTAssertEqual(resolved, activeAssistantId)
    }

    func testTodoCardSkipsActiveAssistantStubWithoutVisibleContent() {
        let activeAssistantId = UUID()
        let tracedAssistantId = UUID()

        let resolved = resolveTodoCardAssistantMessageId(
            messages: [
                ChatMessage(id: tracedAssistantId, role: .assistant, content: "Visible reply"),
                ChatMessage(id: activeAssistantId, role: .assistant, content: ""),
            ],
            activeAssistantMessageId: activeAssistantId,
            latestAssistantMessageIdWithTrace: tracedAssistantId,
            pipelineAssistantMessageId: tracedAssistantId,
            latestVisibleAssistantMessageId: tracedAssistantId
        )

        XCTAssertEqual(resolved, tracedAssistantId)
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
            type: "command_execution",
            payload: ["command": "swift test"]
        )

        XCTAssertEqual(violation?.errorCode, "todo_first_required")
    }

    func testTodoPlanStartPolicyAllowsDiscoveryWithoutTodo() {
        let violation = todoPlanStartPolicyViolation(
            state: ToolStartRequirementsState(),
            type: "mcp_tool_call",
            payload: ["mcp_tool": "coderide_read"]
        )

        XCTAssertNil(violation)
    }

    func testTodoPlanStartPolicyAllowsSkillDiscoveryWithoutTodo() {
        let violation = todoPlanStartPolicyViolation(
            state: ToolStartRequirementsState(),
            type: "mcp_tool_call",
            payload: ["mcp_tool": "coderide_skill"]
        )

        XCTAssertNil(violation)
    }

    func testTodoPlanStartPolicyDoesNotTreatPlanModeActivationAsOperationalWork() {
        let violation = todoPlanStartPolicyViolation(
            state: ToolStartRequirementsState(),
            type: "mcp_tool_call",
            payload: ["mcp_tool": "coderide_activate_plan_mode"]
        )

        XCTAssertNil(violation)
    }

    func testTodoPlanStartPolicyDoesNotTreatSubagentMCPCallAsTodoGatedOperationalWork() {
        let violation = todoPlanStartPolicyViolation(
            state: ToolStartRequirementsState(),
            type: "mcp_tool_call",
            payload: ["mcp_tool": "coderide_subagent_explorer"]
        )

        XCTAssertNil(violation)
    }

    func testTodoCardDoesNotBindToInvisiblePipelineAssistantStub() {
        let visibleAssistantId = UUID()
        let pipelineAssistantId = UUID()

        let resolved = resolveTodoCardAssistantMessageId(
            messages: [
                ChatMessage(id: visibleAssistantId, role: .assistant, content: "Analisi completata"),
                ChatMessage(id: pipelineAssistantId, role: .assistant, content: "")
            ],
            activeAssistantMessageId: nil,
            latestAssistantMessageIdWithTrace: nil,
            pipelineAssistantMessageId: pipelineAssistantId,
            latestVisibleAssistantMessageId: visibleAssistantId
        )

        XCTAssertEqual(resolved, visibleAssistantId)
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

    func testLinearChatHidesPolicyAckMCPCall() {
        XCTAssertFalse(
            shouldShowOperationEventInLinearChat(
                eventType: "mcp_tool_call",
                payload: ["mcp_tool": "coderide_policy_ack", "is_mcp": "true"],
                showTodoCard: false
            )
        )
    }

}
