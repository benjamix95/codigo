import Foundation
import XCTest
@testable import CoderIDE

final class ToolTraceVisibilityTests: XCTestCase {
    func testLiveOperationalEventsBypassPolicyAckVisibilityGate() {
        XCTAssertTrue(
            shouldBypassPolicyAckLiveVisibilityGate(
                type: "command_execution",
                payload: ["command": "swift test"]
            )
        )
        XCTAssertTrue(
            shouldBypassPolicyAckLiveVisibilityGate(
                type: "assistant_update",
                payload: ["group_id": "assistant-1", "output": "Sto controllando il reducer"]
            )
        )
        XCTAssertTrue(
            shouldBypassPolicyAckLiveVisibilityGate(
                type: "agent",
                payload: ["swarm_id": "swarm-coder", "detail": "started"]
            )
        )
        XCTAssertTrue(
            shouldBypassPolicyAckLiveVisibilityGate(
                type: "web_search_started",
                payload: ["query": "pipeline chat"]
            )
        )
        XCTAssertTrue(
            shouldBypassPolicyAckLiveVisibilityGate(
                type: "mcp_tool_call",
                payload: ["tool": "mcp_list_servers", "is_mcp": "true"]
            )
        )
    }

    func testNonLiveUnknownOperationalEventStillNeedsPolicyAckGate() {
        XCTAssertFalse(
            shouldBypassPolicyAckLiveVisibilityGate(
                type: "custom_tool_event",
                payload: ["toolCallId": "tc-camel-ops-1"]
            )
        )
    }

    func testPolicyAckIsIncludedButNotDisplayed() {
        let activity = TaskActivity(
            type: "policy_ack",
            title: "Policy acknowledged",
            payload: ["hash": "abc123"],
            phase: .planning,
            isRunning: false
        )
        XCTAssertTrue(ToolTraceVisibility.shouldInclude(activity: activity))

        let event = makeEvent(type: "policy_ack", payload: ["hash": "abc123"])
        XCTAssertFalse(ToolTraceVisibility.shouldDisplay(event: event))
    }

    func testPolicyAckMCPToolCallIsNotIncludedOrDisplayed() {
        let activity = TaskActivity(
            type: "mcp_tool_call",
            title: "MCP policy ack",
            payload: [
                "mcp_tool": "coderide_policy_ack",
                "is_mcp": "true",
            ],
            phase: .executing,
            isRunning: false
        )
        XCTAssertFalse(ToolTraceVisibility.shouldInclude(activity: activity))

        let event = makeEvent(type: "mcp_tool_call", payload: activity.payload)
        XCTAssertFalse(ToolTraceVisibility.shouldDisplay(event: event))
    }

    func testNamespacedInternalMCPToolCallIsNotIncludedOrDisplayed() {
        let activity = TaskActivity(
            type: "mcp_tool_call",
            title: "MCP debug activation",
            payload: [
                "mcp_tool": "functions.coderide_activate_debug_mode",
                "is_mcp": "true",
            ],
            phase: .executing,
            isRunning: true
        )
        XCTAssertFalse(ToolTraceVisibility.shouldInclude(activity: activity))

        let event = makeEvent(type: "mcp_tool_call", payload: activity.payload)
        XCTAssertFalse(ToolTraceVisibility.shouldDisplay(event: event))
    }

    func testRequiresPolicyAckForOperationalEvents() {
        XCTAssertTrue(
            ToolTraceVisibility.requiresPolicyAck(
                type: "command_execution",
                payload: ["command": "rg policy Sources/"]
            )
        )
        XCTAssertTrue(
            ToolTraceVisibility.requiresPolicyAck(
                type: "file_change",
                payload: ["path": "Sources/App.swift"]
            )
        )
        XCTAssertFalse(
            ToolTraceVisibility.requiresPolicyAck(
                type: "policy_ack",
                payload: ["hash": "abc123"]
            )
        )
    }

    func testNonRealMCPEventIsFiltered() {
        let fakeMCP = TaskActivity(
            type: "mcp_tool_call",
            title: "Search",
            payload: ["tool": "search", "query": "foo"],
            phase: .searching,
            isRunning: false
        )
        XCTAssertFalse(ToolTraceVisibility.shouldInclude(activity: fakeMCP))
    }

    func testNamespacedMCPToolEventIsIncludedAndDisplayed() {
        let namespaced = TaskActivity(
            type: "mcp_tool_call",
            title: "MCP discovery",
            payload: [
                "tool": "functions.mcp_list_servers",
                "is_mcp": "true"
            ],
            phase: .executing,
            isRunning: false
        )

        XCTAssertTrue(ToolTraceVisibility.shouldInclude(activity: namespaced))

        let event = makeEvent(type: "mcp_tool_call", payload: [
            "tool": "functions.mcp_list_servers",
            "is_mcp": "true"
        ])
        XCTAssertTrue(ToolTraceVisibility.shouldDisplay(event: event))
    }

    func testCamelCaseMCPMarkersAreIncludedAndDisplayed() {
        let activity = TaskActivity(
            type: "mcp_tool_call",
            title: "MCP camelCase",
            payload: [
                "mcpTool": "mcp_list_resources",
                "mcpServer": "local",
                "isMcp": "true",
            ],
            phase: .executing,
            isRunning: false
        )

        XCTAssertTrue(ToolTraceVisibility.shouldInclude(activity: activity))
        let event = makeEvent(type: "mcp_tool_call", payload: activity.payload)
        XCTAssertTrue(ToolTraceVisibility.shouldDisplay(event: event))
    }

    func testMCPLikeToolNameWithoutMarkerIsFiltered() {
        let fakeMCP = TaskActivity(
            type: "mcp_tool_call",
            title: "Fake MCP",
            payload: ["tool": "check_mcp_status"],
            phase: .executing,
            isRunning: false
        )
        XCTAssertFalse(ToolTraceVisibility.shouldInclude(activity: fakeMCP))
    }

    func testTodoWriteIsIncludedDisplayedAndDoesNotRequirePolicyAck() {
        let activity = TaskActivity(
            type: "todo_write",
            title: "Todo updated",
            payload: [
                "title": "Implement trace fix",
                "status": "in_progress",
            ],
            phase: .planning,
            isRunning: false
        )

        XCTAssertTrue(ToolTraceVisibility.shouldInclude(activity: activity))
        let event = makeEvent(type: "todo_write", payload: activity.payload)
        XCTAssertTrue(ToolTraceVisibility.shouldDisplay(event: event))
        XCTAssertFalse(
            ToolTraceVisibility.requiresPolicyAck(
                type: "todo_write",
                payload: activity.payload
            )
        )
    }

    func testActivatePlanModeIsNotIncludedAndNotDisplayed() {
        let activity = TaskActivity(
            type: "activate_plan_mode",
            title: "Plan mode auto-activated",
            payload: ["reason": "User requested planning"],
            phase: .planning,
            isRunning: false
        )

        XCTAssertFalse(ToolTraceVisibility.shouldInclude(activity: activity))
        let event = makeEvent(type: "activate_plan_mode", payload: ["reason": "User requested planning"])
        XCTAssertFalse(ToolTraceVisibility.shouldDisplay(event: event))
    }

    func testSkillInvocationIsDisplayed() {
        let event = makeEvent(
            type: "skill_invocation",
            payload: ["skill": "commit", "title": "Skill • commit"]
        )
        XCTAssertTrue(ToolTraceVisibility.shouldDisplay(event: event))
    }

    func testAssistantUpdateIsIncludedAndDisplayedInTrace() {
        let activity = TaskActivity(
            type: "assistant_update",
            title: "Sto rispondendo",
            payload: [
                "detail": "Analizzo il flusso eventi",
                "output": "Analizzo il flusso eventi"
            ],
            phase: .executing,
            isRunning: true
        )

        XCTAssertTrue(ToolTraceVisibility.shouldInclude(activity: activity))
        let event = makeEvent(
            type: "assistant_update",
            payload: [
                "detail": "Analizzo il flusso eventi",
                "output": "Analizzo il flusso eventi"
            ]
        )
        XCTAssertTrue(ToolTraceVisibility.shouldDisplay(event: event))
    }

    func testSkillInvocationActivityIsIncluded() {
        let activity = TaskActivity(
            type: "skill_invocation",
            title: "Skill • commit",
            payload: ["skill": "commit"],
            phase: .executing,
            isRunning: false
        )
        XCTAssertTrue(ToolTraceVisibility.shouldInclude(activity: activity))
    }

    func testSwarmScopedEventRequiresPolicyAckWithSwarmId() {
        XCTAssertTrue(
            ToolTraceVisibility.requiresPolicyAck(
                type: "agent",
                payload: [
                    "title": "orchestrator",
                    "detail": "started",
                    "swarm_id": "orchestrator",
                ]
            )
        )
    }

    func testSwarmScopedEventRequiresPolicyAckWithGroupId() {
        XCTAssertTrue(
            ToolTraceVisibility.requiresPolicyAck(
                type: "agent",
                payload: [
                    "title": "coder",
                    "detail": "running",
                    "group_id": "swarm-coder",
                ]
            )
        )
    }

    func testOperationalPayloadCamelCaseToolCallIdRequiresPolicyAck() {
        XCTAssertTrue(
            ToolTraceVisibility.requiresPolicyAck(
                type: "custom_tool_event",
                payload: ["toolCallId": "tc-camel-ops-1"]
            )
        )
    }

    private func makeEvent(type: String, payload: [String: String]) -> ToolTraceEvent {
        ToolTraceEvent(
            sequence: 1,
            timestamp: Date(),
            providerId: "test",
            conversationId: UUID(),
            assistantMessageId: UUID(),
            type: type,
            title: type,
            detail: nil,
            payload: payload,
            phase: .planning,
            isRunning: false,
            groupId: nil,
            rawKind: "test"
        )
    }
}
