import XCTest
@testable import CoderIDE

class ChatTimelineInterleavingTestCase: XCTestCase {
    func makeEvent(
        sequence: Int,
        title: String,
        type: String = "mcp_tool_call",
        tool: String = "read",
        path: String? = nil,
        query: String? = nil,
        command: String? = nil,
        swarmId: String? = nil,
        timestamp: Date? = nil
    ) -> ToolTraceEvent {
        var payload = ["mcp_tool": tool]
        if let path {
            payload["path"] = path
        }
        if let query {
            payload["query"] = query
        }
        if let command {
            payload["command"] = command
        }
        if let swarmId {
            payload["swarm_id"] = swarmId
        }
        return ToolTraceEvent(
            sequence: sequence,
            timestamp: timestamp ?? Date(timeIntervalSince1970: TimeInterval(sequence)),
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

    func makeBlock(
        id: String = UUID().uuidString,
        kind: ChatTimelineBlockKind,
        text: String = "",
        sequence: Int
    ) -> PersistedChatTimelineBlock {
        PersistedChatTimelineBlock(
            id: id,
            kind: kind,
            text: text,
            sequence: sequence
        )
    }
}
