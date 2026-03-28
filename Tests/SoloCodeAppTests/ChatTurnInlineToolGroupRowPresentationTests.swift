import XCTest
@testable import CoderIDE

final class ChatTurnInlineToolGroupRowPresentationTests: XCTestCase {
    func testReadPresentationUsesLetturaLabelAndFilename() {
        let presentation = ChatTurnInlineToolGroupRowPresentation.make(
            event: makeEvent(
                sequence: 1,
                title: "Read file",
                tool: "read",
                path: "/tmp/ChatTurnView.swift"
            )
        )

        XCTAssertEqual(presentation.actionLabel, "Lettura")
        XCTAssertEqual(presentation.emphasizedText, "ChatTurnView.swift")
        XCTAssertFalse(presentation.usesMonospacedEmphasis)
    }

    func testSearchPresentationUsesRicercaLabel() {
        let presentation = ChatTurnInlineToolGroupRowPresentation.make(
            event: makeEvent(
                sequence: 1,
                title: "Search symbol",
                tool: "codebase_search",
                query: "MessageToolTraceView"
            )
        )

        XCTAssertEqual(presentation.actionLabel, "Ricerca")
        XCTAssertEqual(presentation.emphasizedText, "MessageToolTraceView")
    }

    func testTerminalPresentationUsesMonospacedCommand() {
        let presentation = ChatTurnInlineToolGroupRowPresentation.make(
            event: makeEvent(
                sequence: 1,
                title: "command_execution",
                type: "command_execution",
                tool: "bash",
                command: "swift test --filter ChatTimelineInlineToolGroupingTests"
            )
        )

        XCTAssertEqual(presentation.actionLabel, "Terminale")
        XCTAssertEqual(presentation.emphasizedText, "swift test --filter ChatTimelineInlineToolGroupingTests")
        XCTAssertTrue(presentation.usesMonospacedEmphasis)
    }

    private func makeEvent(
        sequence: Int,
        title: String,
        type: String = "mcp_tool_call",
        tool: String,
        path: String? = nil,
        query: String? = nil,
        command: String? = nil
    ) -> ToolTraceEvent {
        var payload = ["mcp_tool": tool]
        payload["tool"] = tool
        if let path {
            payload["path"] = path
        }
        if let query {
            payload["query"] = query
        }
        if let command {
            payload["command"] = command
        }
        return ToolTraceEvent(
            sequence: sequence,
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            providerId: "codex-cli",
            conversationId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            assistantMessageId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            type: type,
            title: title,
            detail: nil,
            payload: payload,
            phase: .executing,
            isRunning: false,
            groupId: nil,
            rawKind: "raw"
        )
    }
}
