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

    func testLiveTodoCardStaysVisibleWhenOnlyOneSwarmSurfaceIsActive() {
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

    func testLiveTodoCardIsHiddenWhenSwarmStepsAndLiveCardsBothPresent() {
        XCTAssertFalse(
            shouldShowLiveTodoCardInChat(
                hasSwarmSteps: true,
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
        XCTAssertEqual(
            violation?.detail,
            "Emit todo_write before starting real execution with 'command_execution'."
        )
    }

    func testTodoPlanStartPolicyAllowsReadOnlySearchCommandWithoutTodo() {
        let violation = todoPlanStartPolicyViolation(
            state: ToolStartRequirementsState(),
            type: "command_execution",
            payload: ["command": "grep -R \"@State\" App/SoloCodeApp"]
        )

        XCTAssertNil(violation)
    }

    func testTodoPlanStartPolicyAllowsReadOnlyFileReadCommandWithoutTodo() {
        let violation = todoPlanStartPolicyViolation(
            state: ToolStartRequirementsState(),
            type: "command_execution",
            payload: ["command": "sed -n '1,40p' App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift"]
        )

        XCTAssertNil(violation)
    }

    func testTodoPlanStartPolicyAllowsDiscoveryWithoutTodo() {
        let violation = todoPlanStartPolicyViolation(
            state: ToolStartRequirementsState(),
            type: "mcp_tool_call",
            payload: ["mcp_tool": "coderide_read"]
        )

        XCTAssertNil(violation)
    }

    func testTodoPlanStartPolicyAllowsMCPResourceListingWithoutTodo() {
        let tools = [
            "list_mcp_resources",
            "list_mcp_resource_templates",
            "mcp_list_resources",
            "mcp_list_prompts",
        ]

        for tool in tools {
            let violation = todoPlanStartPolicyViolation(
                state: ToolStartRequirementsState(),
                type: "mcp_tool_call",
                payload: ["mcp_tool": tool]
            )

            XCTAssertNil(violation, "Expected discovery tool \(tool) to bypass todo-first gating")
        }
    }

    func testTodoPlanStartPolicyAllowsNamespacedMCPResourceListingWithoutTodo() {
        let tools = [
            "functions.list_mcp_resources",
            "functions.list_mcp_resource_templates",
            "functions.mcp_list_resources",
            "functions.mcp_list_prompts",
        ]

        for tool in tools {
            let violation = todoPlanStartPolicyViolation(
                state: ToolStartRequirementsState(),
                type: "mcp_tool_call",
                payload: ["mcp_tool": tool]
            )

            XCTAssertNil(violation, "Expected namespaced discovery tool \(tool) to bypass todo-first gating")
        }
    }

    func testTodoPlanStartPolicyAllowsMCPResourceListingFromCamelCasePayloadWithoutTodo() {
        let tools = [
            "list_mcp_resources",
            "functions.list_mcp_resource_templates",
            "mcp_list_resources",
            "functions.mcp_list_prompts",
        ]

        for tool in tools {
            let violation = todoPlanStartPolicyViolation(
                state: ToolStartRequirementsState(),
                type: "mcp_tool_call",
                payload: ["mcpTool": tool]
            )

            XCTAssertNil(violation, "Expected camelCase payload discovery tool \(tool) to bypass todo-first gating")
        }
    }

    func testTodoPlanStartPolicyAllowsDirectDiscoveryEventTypesWithoutTodo() {
        let eventTypes = [
            "list_mcp_resources",
            "list_mcp_resource_templates",
            "mcp_list_resources",
            "mcp_list_prompts",
            "functions.list_mcp_resources",
        ]

        for eventType in eventTypes {
            let violation = todoPlanStartPolicyViolation(
                state: ToolStartRequirementsState(),
                type: eventType,
                payload: [:]
            )

            XCTAssertNil(violation, "Expected direct discovery event \(eventType) to bypass todo-first gating")
        }
    }

    func testTodoPlanStartPolicyAllowsReadOnlyShellInspectionWithoutTodo() {
        let commands = [
            "rg ChatPanelView App/SoloCodeApp/Sources",
            "grep -n todo_write README.md",
            "git diff --stat",
            "ls -la",
            "pwd",
        ]

        for command in commands {
            let violation = todoPlanStartPolicyViolation(
                state: ToolStartRequirementsState(),
                type: "command_execution",
                payload: ["command": command]
            )

            XCTAssertNil(violation, "Expected read-only command to bypass todo-first gating: \(command)")
        }
    }

    func testTodoPlanStartPolicyAllowsSkillDiscoveryWithoutTodo() {
        let violation = todoPlanStartPolicyViolation(
            state: ToolStartRequirementsState(),
            type: "mcp_tool_call",
            payload: ["mcp_tool": "coderide_skill"]
        )

        XCTAssertNil(violation)
    }

    func testTodoPlanStartPolicyAllowsAuditDiscoveryWithoutTodo() {
        let violation = todoPlanStartPolicyViolation(
            state: ToolStartRequirementsState(),
            type: "mcp_tool_call",
            payload: ["mcp_tool": "coderide_audit_bug_test_gaps"]
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

    func testLinearChatHidesNamespacedInternalMCPCalls() {
        XCTAssertFalse(
            shouldShowOperationEventInLinearChat(
                eventType: "mcp_tool_call",
                payload: ["mcp_tool": "functions.coderide_policy_ack", "is_mcp": "true"],
                showTodoCard: false
            )
        )
        XCTAssertFalse(
            shouldShowOperationEventInLinearChat(
                eventType: "mcp_tool_call",
                payload: ["mcp_tool": "functions.coderide_activate_debug_mode", "is_mcp": "true"],
                showTodoCard: false
            )
        )
    }

    func testLinearChatKeepsRealMCPCallsVisibleInCompactTrace() {
        XCTAssertTrue(
            shouldShowOperationEventInLinearChat(
                eventType: "mcp_tool_call",
                payload: ["mcp_tool": "coderide_read", "path": "README.md", "is_mcp": "true"],
                showTodoCard: false
            )
        )
    }

}
