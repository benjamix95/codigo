import XCTest
@testable import CoderIDE

final class ChatPipelineTimelineStateTests: XCTestCase {
    func testReducerBuildsInterleavedTimelineBlocks() {
        let conversationId = UUID()
        let assistantMessageId = UUID()
        let turnId = UUID().uuidString
        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId
        )

        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: turnId,
                sequence: 1,
                source: "codex",
                kind: .textDelta,
                payload: ["stream_id": "main", "delta": "Prima parte"]
            )
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: turnId,
                sequence: 2,
                source: "codex",
                kind: .toolTraceArtifact,
                payload: ["artifact_id": "tool-1", "title": "Read", "detail": "cat file.swift"]
            )
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: turnId,
                sequence: 3,
                source: "codex",
                kind: .textDelta,
                payload: ["stream_id": "main", "delta": " Seconda parte"]
            )
        )

        XCTAssertEqual(
            state.timelineSegments.map(\.kind),
            [.text, .toolUse, .text]
        )
        XCTAssertEqual(state.textSegments, ["Prima parte", " Seconda parte"])
        XCTAssertEqual(state.timelineNextSequence, 3)

        let blocks = state.blocks
        XCTAssertEqual(blocks.map(\.kind), [.primaryText, .toolMarker, .primaryText, .toolTrace])
        XCTAssertEqual(blocks.map(\.sequence), [0, 1, 2, 0])
        XCTAssertEqual(blocks[0].text, "Prima parte")
        XCTAssertEqual(blocks[2].text, " Seconda parte")
    }

    func testReducerSplitsTextWhenToolTraceArtifactHasEmptyDetail() {
        let conversationId = UUID()
        let assistantMessageId = UUID()
        let turnId = UUID().uuidString
        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId
        )

        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: turnId,
                sequence: 1,
                source: "codex",
                kind: .textDelta,
                payload: ["stream_id": "main", "delta": "Prima parte"]
            )
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: turnId,
                sequence: 2,
                source: "codex",
                kind: .toolTraceArtifact,
                payload: ["artifact_id": "tool-1", "title": "Read"]
            )
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: turnId,
                sequence: 3,
                source: "codex",
                kind: .textDelta,
                payload: ["stream_id": "main", "delta": "Dopo tool"]
            )
        )

        XCTAssertEqual(
            state.timelineSegments.map(\.kind),
            [.text, .toolUse, .text]
        )
        XCTAssertEqual(state.textSegments, ["Prima parte", "Dopo tool"])
        let blocks = state.blocks
        XCTAssertEqual(blocks.map(\.kind), [.primaryText, .toolMarker, .primaryText])
    }

    func testReducerConsecutiveToolTraceArtifactsEachInsertsMarker() {
        let conversationId = UUID()
        let assistantMessageId = UUID()
        let turnId = UUID().uuidString
        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: turnId,
                sequence: 1,
                source: "codex",
                kind: .textDelta,
                payload: ["stream_id": "main", "delta": "Start"]
            )
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: turnId,
                sequence: 2,
                source: "codex",
                kind: .toolTraceArtifact,
                payload: ["artifact_id": "tool-1", "title": "T1"]
            )
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: turnId,
                sequence: 3,
                source: "codex",
                kind: .toolTraceArtifact,
                payload: ["artifact_id": "tool-2", "title": "T2"]
            )
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: turnId,
                sequence: 4,
                source: "codex",
                kind: .textDelta,
                payload: ["stream_id": "main", "delta": " End"]
            )
        )
        XCTAssertEqual(
            state.timelineSegments.map(\.kind),
            [.text, .toolUse, .toolUse, .text]
        )
        let markerBlocks = state.blocks.filter { $0.kind == .toolMarker }
        XCTAssertEqual(markerBlocks.count, 2)
    }

    func testReconcileRestoresSwiftTimelineWhenRustReturnsEmptySegments() {
        let conversationId = UUID()
        let assistantMessageId = UUID()
        let turnId = UUID().uuidString
        var previous = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId
        )
        previous.timelineSegments = [
            ChatTimelineSegment(kind: .text, index: 0, sequence: 0),
            ChatTimelineSegment(kind: .toolUse, index: 0, sequence: 1),
        ]
        previous.timelineNextSequence = 2
        previous.textSegments = ["Hello"]

        var rustLike = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId
        )
        rustLike.textByStreamId["main"] = "Hello world"
        rustLike.orderedTextStreamIds = ["main"]
        rustLike.timelineSegments = []
        rustLike.timelineNextSequence = 0

        let merged = rustLike.reconcilingTimelineWhenRustReturnedEmptyWhileSwiftHadToolMarkers(previous: previous)
        XCTAssertEqual(merged.timelineSegments, previous.timelineSegments)
        XCTAssertEqual(merged.timelineNextSequence, 2)
        XCTAssertEqual(merged.textSegments, ["Hello"])
    }

    func testBridgeStateRoundTripPreservesTimelineSegments() throws {
        let conversationId = UUID()
        let assistantMessageId = UUID()
        let turnId = UUID().uuidString
        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId
        )
        state.textByStreamId["main"] = "Prima Seconda"
        state.orderedTextStreamIds = ["main"]
        state.textSegments = ["Prima", "Seconda"]
        state.timelineSegments = [
            ChatTimelineSegment(kind: .text, index: 0, sequence: 0),
            ChatTimelineSegment(kind: .toolUse, index: 0, sequence: 1),
            ChatTimelineSegment(kind: .text, index: 1, sequence: 2),
        ]
        state.timelineNextSequence = 3

        let data = try JSONEncoder().encode(MainChatBridgeState(state))
        let restored = try JSONDecoder().decode(MainChatBridgeState.self, from: data).chatTurnState

        XCTAssertEqual(restored.textSegments, ["Prima", "Seconda"])
        XCTAssertEqual(
            restored.timelineSegments,
            [
                ChatTimelineSegment(kind: .text, index: 0, sequence: 0),
                ChatTimelineSegment(kind: .toolUse, index: 0, sequence: 1),
                ChatTimelineSegment(kind: .text, index: 1, sequence: 2),
            ]
        )
        XCTAssertEqual(restored.timelineNextSequence, 3)
        XCTAssertEqual(restored.blocks.map(\.kind), [.primaryText, .toolMarker, .primaryText])
        XCTAssertEqual(restored.blocks.map(\.sequence), [0, 1, 2])
    }
}
