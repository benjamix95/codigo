import XCTest
@testable import CoderIDE

final class ChatReasoningStreamReducerTests: XCTestCase {
    func testCodexSuppressesReasoningPresentation() {
        XCTAssertEqual(
            ChatReasoningPresentationPolicy.mode(
                providerId: "codex-cli",
                separateCodexThinkingMessagesEnabled: false
            ),
            .suppressed
        )
    }

    func testSuppressReasoningUsesFallbackWhenMessageMetadataProviderIdMissing() {
        XCTAssertTrue(
            ChatReasoningPresentationPolicy.shouldSuppressReasoningUI(
                messageProviderId: "",
                fallbackTurnProviderId: "codex-cli"
            )
        )
        XCTAssertFalse(
            ChatReasoningPresentationPolicy.shouldSuppressReasoningUI(
                messageProviderId: "",
                fallbackTurnProviderId: "claude-cli"
            )
        )
    }

    func testNonCodexProvidersUseInlineReasoningPresentationInMainChat() {
        let providerIds = [
            "claude-cli",
            "gemini-cli",
            "openai-api",
        ]

        for providerId in providerIds {
            XCTAssertEqual(
                ChatReasoningPresentationPolicy.mode(
                    providerId: providerId,
                    separateCodexThinkingMessagesEnabled: false
                ),
                .inline,
                "Expected \(providerId) to render reasoning inline in main chat"
            )
        }
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

    func testMainChatInlineReasoningGroupIdCollapsesProviderSpecificGroups() {
        XCTAssertEqual(
            mainChatInlineReasoningGroupId(
                providerId: "claude-cli",
                payload: ["group_id": "thinking-1"]
            ),
            "reasoning-stream"
        )
        XCTAssertEqual(
            mainChatInlineReasoningGroupId(
                providerId: "openai-api",
                payload: ["group_id": "reasoning-42"]
            ),
            "reasoning-stream"
        )
    }

    func testMainChatInlineReasoningGroupIdPreservesCodexIntermediateTurnsBucket() {
        XCTAssertEqual(
            mainChatInlineReasoningGroupId(
                providerId: "codex-cli",
                payload: ["group_id": "codex-intermediate-turns"]
            ),
            "codex-intermediate-turns"
        )
    }
}
