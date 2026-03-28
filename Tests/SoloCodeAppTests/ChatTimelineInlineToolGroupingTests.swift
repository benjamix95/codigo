import XCTest
@testable import CoderIDE

final class ChatTimelineInlineToolGroupingTests: XCTestCase {
    func testInlineGroupingPolicyKeepsEditEventsVisibleOutsideCollapsedGroups() {
        let blocks = [
            PersistedChatTimelineBlock(id: "text-0", kind: .primaryText, text: "Start", sequence: 0),
            PersistedChatTimelineBlock(id: "text-1", kind: .primaryText, text: "End", sequence: 5),
        ]
        let events = [
            makeEvent(sequence: 1, title: "Read A", tool: "read", path: "/tmp/A.swift"),
            makeEvent(sequence: 2, title: "Read B", tool: "read_range", path: "/tmp/B.swift"),
            makeEvent(
                sequence: 3,
                title: "apply_patch",
                type: "command_execution",
                tool: "functions.apply_patch",
                path: "/tmp/C.swift",
                patch: "@@ -1 +1 @@\n-old\n+new"
            ),
            makeEvent(
                sequence: 4,
                title: "Created D.swift",
                type: "create_file",
                tool: "create_file",
                path: "/tmp/D.swift"
            ),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: events)
        let groups = segments.compactMap { segment -> ChatTurnToolEventGroup? in
            if case .toolGroup(_, let group, _) = segment { return group }
            return nil
        }
        let visibleToolEvents = segments.compactMap { segment -> ToolTraceEvent? in
            if case .toolEvent(_, let event, _) = segment { return event }
            return nil
        }

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.category, .exploration)
        XCTAssertEqual(groups.first?.events.map(\.sequence), [1, 2])
        XCTAssertEqual(visibleToolEvents.map(\.sequence), [3, 4])
    }

    func testInlineGroupingPolicyStillCollapsesTerminalEvents() {
        let blocks = [
            PersistedChatTimelineBlock(id: "text-0", kind: .primaryText, text: "Start", sequence: 0),
            PersistedChatTimelineBlock(id: "text-1", kind: .primaryText, text: "End", sequence: 3),
        ]
        let events = [
            makeEvent(sequence: 1, title: "bash", type: "command_execution", tool: "bash", command: "swift test"),
            makeEvent(sequence: 2, title: "bash", type: "command_execution", tool: "bash", command: "swift build"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: events)

        XCTAssertEqual(
            segments.filter {
                if case .toolGroup = $0 { return true }
                return false
            }.count,
            1
        )
        XCTAssertEqual(
            segments.filter {
                if case .toolEvent = $0 { return true }
                return false
            }.count,
            0
        )
    }

    private func makeEvent(
        sequence: Int,
        title: String,
        type: String = "mcp_tool_call",
        tool: String,
        path: String? = nil,
        command: String? = nil,
        patch: String? = nil
    ) -> ToolTraceEvent {
        var payload = ["mcp_tool": tool]
        payload["tool"] = tool
        if let path {
            payload["path"] = path
        }
        if let command {
            payload["command"] = command
        }
        if let patch {
            payload["patch"] = patch
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
