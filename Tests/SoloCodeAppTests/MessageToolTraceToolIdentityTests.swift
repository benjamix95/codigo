import XCTest
import SwiftUI
@testable import CoderIDE

final class MessageToolTraceToolIdentityTests: XCTestCase {
    func testCollapsedSummaryCountsReadSearchAndListOperationsFromMCPTools() {
        let events = [
            makeEvent(
                sequence: 1,
                type: "mcp_tool_call",
                payload: [
                    "mcp_tool": "read",
                    "path": "App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnView.swift",
                ]
            ),
            makeEvent(
                sequence: 2,
                type: "semantic_search",
                payload: [
                    "tool": "semantic_search",
                    "query": "chat activity card collapse",
                ]
            ),
            makeEvent(
                sequence: 3,
                type: "mcp_tool_call",
                payload: [
                    "mcp_tool": "codebase_search",
                    "query": "MessageToolTraceView",
                ]
            ),
            makeEvent(
                sequence: 4,
                type: "mcp_tool_call",
                payload: [
                    "mcp_tool": "find_files",
                    "pattern": "*Trace*.swift",
                ]
            ),
            makeEvent(
                sequence: 5,
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
            sequence: 1,
            type: "mcp_tool_call",
            payload: ["mcp_tool": "find_files"]
        )

        let identity = MessageToolTraceToolIdentity.resolve(for: event)

        XCTAssertEqual(identity.symbolName, "folder")
    }

    func testHeaderTitleUsesItalianRunningCopy() {
        let event = makeEvent(
            sequence: 1,
            type: "mcp_tool_call",
            payload: ["mcp_tool": "read", "path": "README.md"],
            isRunning: true
        )
        let view = MessageToolTraceView(events: [event], workspaceHints: [], onOpenFile: { _ in })
        let derived = MessageToolTraceView.DerivedState(
            events: [event],
            isExpanded: false,
            runningCompactLimit: 8,
            collapser: ToolTraceEventCollapser.collapseSupersededToolStates
        )

        XCTAssertEqual(view.headerTitle(derived: derived), "1 operazione in corso...")
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
            title: "Evento \(sequence)",
            detail: nil,
            payload: payload,
            phase: .executing,
            isRunning: isRunning,
            groupId: nil,
            rawKind: "raw"
        )
    }
}
