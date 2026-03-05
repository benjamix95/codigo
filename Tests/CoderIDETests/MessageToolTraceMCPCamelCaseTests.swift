import XCTest
@testable import CoderIDE

final class MessageToolTraceMCPCamelCaseTests: XCTestCase {
    func testPayloadValueReadsCamelCaseAliases() {
        let view = makeView()
        let payload: [String: String] = [
            "mcpServer": "local.server",
            "serverId": "backup.server",
            "mcpTool": "mcp_list_resources",
        ]

        XCTAssertEqual(
            view.payloadValue(payload, keys: ["mcp_server", "mcpServer", "server_id", "serverId"]),
            "local.server"
        )
        XCTAssertEqual(
            view.payloadValue(payload, keys: ["mcp_tool", "mcpTool"]),
            "mcp_list_resources"
        )
    }

    func testCompactDetailUsesCamelCaseMCPFields() {
        let view = makeView()
        let event = makeEvent(
            sequence: 1,
            type: "mcp_tool_call",
            payload: [
                "mcpTool": "mcp_list_resources",
                "mcpServer": "local.server",
            ]
        )

        XCTAssertEqual(view.compactDetail(for: event), "mcp_list_resources")
    }

    func testCollapsedSummaryCountsCamelCaseMCPKinds() {
        let events = [
            makeEvent(sequence: 1, type: "mcp_tool_call", payload: ["mcpTool": "mcp_batch"]),
            makeEvent(sequence: 2, type: "mcp_tool_call", payload: ["mcpTool": "mcp_list_resources"]),
            makeEvent(sequence: 3, type: "mcp_tool_call", payload: ["mcpTool": "mcp_list_prompts"]),
        ]

        let summary = MessageToolTraceView.DerivedState.computeCollapsedSummary(orderedEvents: events)

        XCTAssertEqual(summary, "MCP 3 calls (1 batch, 1 resource, 1 prompt)")
    }

    private func makeView() -> MessageToolTraceView {
        MessageToolTraceView(
            events: [],
            workspaceHints: [],
            onOpenFile: { _ in }
        )
    }

    private func makeEvent(
        sequence: Int,
        type: String,
        payload: [String: String]
    ) -> ToolTraceEvent {
        ToolTraceEvent(
            sequence: sequence,
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            providerId: "codex-cli",
            conversationId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            assistantMessageId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            type: type,
            title: "Event \(sequence)",
            detail: nil,
            payload: payload,
            phase: .executing,
            isRunning: false,
            groupId: nil,
            rawKind: "raw"
        )
    }
}
