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

        XCTAssertEqual(summary, "batch, list_prompts +1")
    }

    func testSemanticSearchStartedUsesDedicatedSemanticIcon() {
        let event = makeEvent(
            sequence: 1,
            type: "read_batch_started",
            payload: ["tool": "functions.semantic_search"]
        )

        let identity = MessageToolTraceToolIdentity.resolve(for: event)

        XCTAssertEqual(identity.symbolName, "brain")
    }

    func testWriteToolUsesDedicatedWriteIcon() {
        let event = makeEvent(
            sequence: 1,
            type: "file_change",
            payload: ["tool": "write", "path": "App/SoloCodeApp/Sources/Trace.swift"]
        )

        let identity = MessageToolTraceToolIdentity.resolve(for: event)

        XCTAssertEqual(identity.symbolName, "square.and.pencil")
    }

    func testCollapsedSummaryCountsReadSearchAndListOperationsFromMCPTools() {
        let events = [
            makeEvent(
                sequence: 4,
                type: "mcp_tool_call",
                payload: [
                    "mcp_tool": "read",
                    "path": "App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnView.swift",
                ]
            ),
            makeEvent(
                sequence: 5,
                type: "semantic_search",
                payload: [
                    "tool": "semantic_search",
                    "query": "chat activity card collapse",
                ]
            ),
            makeEvent(
                sequence: 6,
                type: "mcp_tool_call",
                payload: [
                    "mcp_tool": "codebase_search",
                    "query": "MessageToolTraceView",
                ]
            ),
            makeEvent(
                sequence: 7,
                type: "mcp_tool_call",
                payload: [
                    "mcp_tool": "find_files",
                    "pattern": "*Trace*.swift",
                ]
            ),
            makeEvent(
                sequence: 8,
                type: "mcp_tool_call",
                payload: [
                    "mcp_tool": "read_range",
                    "path": "App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView.swift",
                ]
            ),
        ]

        let summary = MessageToolTraceView.DerivedState.computeCollapsedSummary(orderedEvents: events)

        XCTAssertEqual(summary, "2 file letti · 2 ricerche · 1 elenco")
    }

    func testFindFilesUsesFolderIconInsteadOfSearchIcon() {
        let event = makeEvent(
            sequence: 9,
            type: "mcp_tool_call",
            payload: ["mcp_tool": "find_files"]
        )

        let identity = MessageToolTraceToolIdentity.resolve(for: event)

        XCTAssertEqual(identity.symbolName, "folder")
    }

    func testHeaderTitleUsesCollapsedSummaryWhileRunning() {
        let event = makeEvent(
            sequence: 10,
            type: "mcp_tool_call",
            payload: ["mcp_tool": "read", "path": "README.md"],
            isRunning: true
        )
        let view = makeView(events: [event])
        let derived = MessageToolTraceView.DerivedState(
            events: [event],
            isExpanded: false,
            runningCompactLimit: 8,
            collapser: ToolTraceEventCollapser.collapseSupersededToolStates
        )

        XCTAssertEqual(view.headerTitle(derived: derived), "1 file letto · read")
    }

    private func makeView(events: [ToolTraceEvent] = []) -> MessageToolTraceView {
        MessageToolTraceView(
            events: events,
            workspaceHints: [],
            onOpenFile: { _ in }
        )
    }

    private func makeEvent(
        sequence: Int,
        type: String,
        payload: [String: String],
        isRunning: Bool = false
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
            isRunning: isRunning,
            groupId: nil,
            rawKind: "raw"
        )
    }
}
