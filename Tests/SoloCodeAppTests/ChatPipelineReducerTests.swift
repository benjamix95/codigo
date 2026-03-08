import XCTest
@testable import CoderIDE

final class ChatPipelineReducerTests: XCTestCase {
    func testReducerMaintainsStablePrimaryTextOrderAcrossStreamIDs() {
        let conversationId = UUID()
        let assistantMessageId = UUID()
        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: assistantMessageId.uuidString,
            orderedTextStreamIds: ["task-1", "task-2"]
        )

        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: assistantMessageId.uuidString,
                sequence: 1,
                source: "pipeline",
                kind: .textDelta,
                payload: ["stream_id": "task-2", "delta": "second"]
            )
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: assistantMessageId.uuidString,
                sequence: 2,
                source: "pipeline",
                kind: .textDelta,
                payload: ["stream_id": "task-1", "delta": "first "]
            )
        )

        XCTAssertEqual(state.primaryTextSnapshot, "first second")
    }

    func testReducerKeepsMermaidAsArtifactInsteadOfReplacingPrimaryText() {
        let conversationId = UUID()
        let assistantMessageId = UUID()
        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: assistantMessageId.uuidString
        )

        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: assistantMessageId.uuidString,
                sequence: 1,
                source: "codex",
                kind: .textReplace,
                payload: ["replacement": "Primary response", "stream_id": "main"]
            )
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: assistantMessageId.uuidString,
                sequence: 2,
                source: "codex",
                kind: .mermaidArtifact,
                payload: ["artifact_id": "mermaid-1", "title": "Flow", "code": "graph TD; A-->B;"]
            )
        )

        XCTAssertEqual(state.primaryTextSnapshot, "Primary response")
        XCTAssertEqual(state.blocks.first?.kind, .primaryText)
        XCTAssertTrue(state.blocks.contains(where: { $0.kind == .mermaid }))
    }
}
