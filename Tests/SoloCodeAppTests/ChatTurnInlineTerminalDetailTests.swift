import XCTest
@testable import CoderIDE

final class ChatTurnInlineTerminalDetailTests: XCTestCase {
    func testBuildsTerminalDetailFromCommandExecutionPayload() {
        let event = makeEvent(
            type: "command_execution",
            tool: "bash",
            payload: [
                "command": "swift test",
                "output": "Running tests...",
                "stderr": "warning",
                "exitCode": "0",
                "cwd": "/tmp/work",
            ],
            isRunning: true
        )

        let detail = ChatTurnInlineTerminalDetail.from(
            event: event,
            normalizedTool: "bash"
        )

        XCTAssertEqual(detail?.command, "swift test")
        XCTAssertEqual(detail?.output, "Running tests...")
        XCTAssertEqual(detail?.stderr, "warning")
        XCTAssertEqual(detail?.exitCode, "0")
        XCTAssertEqual(detail?.cwd, "/tmp/work")
        XCTAssertTrue(detail?.hasVisibleDetails == true)
    }

    func testReturnsNilForNonTerminalEvent() {
        let event = makeEvent(
            type: "mcp_tool_call",
            tool: "read",
            payload: ["path": "README.md"],
            isRunning: false
        )

        let detail = ChatTurnInlineTerminalDetail.from(
            event: event,
            normalizedTool: "read"
        )

        XCTAssertNil(detail)
    }

    private func makeEvent(
        type: String,
        tool: String,
        payload: [String: String],
        isRunning: Bool
    ) -> ToolTraceEvent {
        var fullPayload = payload
        fullPayload["tool"] = tool
        return ToolTraceEvent(
            sequence: 1,
            timestamp: Date(timeIntervalSince1970: 1),
            providerId: "codex-cli",
            conversationId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            assistantMessageId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            type: type,
            title: "terminal",
            detail: nil,
            payload: fullPayload,
            phase: .executing,
            isRunning: isRunning,
            groupId: nil,
            rawKind: "raw"
        )
    }
}
