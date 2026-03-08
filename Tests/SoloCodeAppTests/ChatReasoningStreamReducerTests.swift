import XCTest
@testable import CoderIDE

final class ChatReasoningStreamReducerTests: XCTestCase {
    func testCodexUsesInlineReasoningPresentationByDefault() {
        XCTAssertEqual(
            ChatReasoningPresentationPolicy.mode(
                providerId: "codex-cli",
                separateCodexThinkingMessagesEnabled: false
            ),
            .inline
        )
    }

    func testReducerMergesChunksIntoSingleReasoningBlock() {
        let initial = ChatReasoningStreamReducer.State(
            blocks: [],
            text: nil,
            segments: []
        )

        let afterFirstChunk = ChatReasoningStreamReducer.apply(
            output: "Planning next move",
            groupId: "reasoning-stream",
            state: initial,
            sequentialStreamingLayoutEnabled: false,
            streamingSegmentTurnIndex: 0
        )
        let afterSecondChunk = ChatReasoningStreamReducer.apply(
            output: "Planning next move\nReading files",
            groupId: "reasoning-stream",
            state: afterFirstChunk,
            sequentialStreamingLayoutEnabled: false,
            streamingSegmentTurnIndex: 0
        )

        XCTAssertEqual(afterSecondChunk.blocks.count, 1)
        XCTAssertEqual(afterSecondChunk.blocks.first?.id, "reasoning-stream")
        XCTAssertEqual(afterSecondChunk.blocks.first?.text, "Planning next move\nReading files")
        XCTAssertEqual(afterSecondChunk.text, "Planning next move\nReading files")
    }

    func testInlineReasoningUpdatesOnlyForSelectedConversation() {
        let selectedConversationId = UUID()

        XCTAssertTrue(
            shouldUpdateInlineReasoningState(
                eventConversationId: selectedConversationId,
                selectedConversationId: selectedConversationId
            )
        )
        XCTAssertFalse(
            shouldUpdateInlineReasoningState(
                eventConversationId: UUID(),
                selectedConversationId: selectedConversationId
            )
        )
        XCTAssertFalse(
            shouldUpdateInlineReasoningState(
                eventConversationId: nil,
                selectedConversationId: selectedConversationId
            )
        )
    }
}
