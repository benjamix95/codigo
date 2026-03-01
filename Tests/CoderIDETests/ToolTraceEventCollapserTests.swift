import XCTest
@testable import CoderIDE

final class ToolTraceEventCollapserTests: XCTestCase {
    func testCollapsesByEventIdWhenToolCallIdIsMissing() {
        let started = makeEvent(
            sequence: 1,
            type: "bash",
            isRunning: true,
            payload: [
                "id": "cmd-42",
                "status": "started",
                "command": "git status --short",
            ]
        )
        let completed = makeEvent(
            sequence: 2,
            type: "bash",
            isRunning: false,
            payload: [
                "id": "cmd-42",
                "status": "completed",
                "command": "git status --short",
                "output": "clean",
            ]
        )

        let collapsed = ToolTraceEventCollapser.collapseSupersededToolStates([started, completed])

        XCTAssertEqual(collapsed.count, 1)
        XCTAssertEqual(collapsed.first?.payload["status"], "completed")
        XCTAssertEqual(collapsed.first?.isRunning, false)
    }

    func testCollapsesByToolCallIdAcrossDifferentEventIds() {
        let started = makeEvent(
            sequence: 1,
            type: "mcp_tool_call",
            isRunning: true,
            payload: [
                "tool_call_id": "tc-1",
                "id": "raw-start",
                "status": "started",
            ]
        )
        let completed = makeEvent(
            sequence: 2,
            type: "mcp_tool_call",
            isRunning: false,
            payload: [
                "tool_call_id": "tc-1",
                "id": "raw-complete",
                "status": "completed",
            ]
        )

        let collapsed = ToolTraceEventCollapser.collapseSupersededToolStates([started, completed])

        XCTAssertEqual(collapsed.count, 1)
        XCTAssertEqual(collapsed.first?.payload["tool_call_id"], "tc-1")
        XCTAssertEqual(collapsed.first?.payload["status"], "completed")
        XCTAssertEqual(collapsed.first?.isRunning, false)
    }

    func testCollapsesByNonSwarmGroupIdFallback() {
        let started = makeEvent(
            sequence: 10,
            type: "command_execution",
            isRunning: true,
            payload: [
                "group_id": "cmd-group-7",
                "status": "started",
                "command": "git push",
            ],
            groupId: "cmd-group-7"
        )
        let completed = makeEvent(
            sequence: 11,
            type: "command_execution",
            isRunning: false,
            payload: [
                "group_id": "cmd-group-7",
                "status": "completed",
                "command": "git push",
            ],
            groupId: "cmd-group-7"
        )

        let collapsed = ToolTraceEventCollapser.collapseSupersededToolStates([started, completed])

        XCTAssertEqual(collapsed.count, 1)
        XCTAssertEqual(collapsed.first?.payload["status"], "completed")
    }

    func testDoesNotCollapseWhenOnlySwarmGroupIdIsAvailable() {
        let started = makeEvent(
            sequence: 20,
            type: "command_execution",
            isRunning: true,
            payload: [
                "group_id": "swarm-coder",
                "status": "started",
            ],
            groupId: "swarm-coder"
        )
        let completed = makeEvent(
            sequence: 21,
            type: "command_execution",
            isRunning: false,
            payload: [
                "group_id": "swarm-coder",
                "status": "completed",
            ],
            groupId: "swarm-coder"
        )

        let collapsed = ToolTraceEventCollapser.collapseSupersededToolStates([started, completed])

        XCTAssertEqual(collapsed.count, 2)
        XCTAssertEqual(collapsed.filter(\.isRunning).count, 1)
    }

    private func makeEvent(
        sequence: Int,
        type: String,
        isRunning: Bool,
        payload: [String: String],
        groupId: String? = nil
    ) -> ToolTraceEvent {
        ToolTraceEvent(
            sequence: sequence,
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            providerId: "codex-cli",
            conversationId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            assistantMessageId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            type: type,
            title: "Event \(sequence)",
            detail: payload["status"],
            payload: payload,
            phase: .executing,
            isRunning: isRunning,
            groupId: groupId,
            rawKind: "raw"
        )
    }
}
