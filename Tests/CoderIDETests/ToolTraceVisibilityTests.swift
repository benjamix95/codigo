import Foundation
import XCTest
@testable import CoderIDE

final class ToolTraceVisibilityTests: XCTestCase {
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
