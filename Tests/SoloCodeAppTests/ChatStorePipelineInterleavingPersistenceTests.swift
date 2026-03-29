import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class ChatStorePipelineInterleavingPersistenceTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName = ""

    override func setUpWithError() throws {
        suiteName = "ChatStorePipelineInterleavingPersistenceTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        userDefaults?.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = ""
    }

    func testPipelineTimelinePreferenceDetectsRicherInterleavedStructure() {
        let localBlocks = [
            PersistedChatTimelineBlock(
                id: "primary-text",
                kind: .primaryText,
                text: "Prima parte Seconda parte",
                sequence: 0
            ),
            PersistedChatTimelineBlock(
                id: "tool-marker-1",
                kind: .toolMarker,
                sequence: 1
            ),
        ]
        let pipelineBlocks = [
            PersistedChatTimelineBlock(id: "text-0", kind: .primaryText, text: "Prima parte", sequence: 0),
            PersistedChatTimelineBlock(id: "tool-marker-1", kind: .toolMarker, sequence: 1),
            PersistedChatTimelineBlock(id: "text-1", kind: .primaryText, text: "Seconda parte", sequence: 2),
        ]

        XCTAssertTrue(
            shouldPreferPipelineTimelineBlocks(
                localBlocks: localBlocks,
                pipelineBlocks: pipelineBlocks
            )
        )
    }

    func testUpdateAssistantMessagePipelineStatePreservesInterleavedPrimaryBlocksWhenRustApplySucceeds() throws {
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", reviewCoreLibraryPath(from: #filePath), 1)
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        unsetenv("SOLOCODE_REVIEW_CORE_DISABLE_RUST")
        ReviewCoreBridge.resetForTests()
        defer {
            unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
            unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
            unsetenv("SOLOCODE_REVIEW_CORE_DISABLE_RUST")
            ReviewCoreBridge.resetForTests()
        }

        let store = ChatStore(userDefaults: userDefaults)
        let conversationId = try XCTUnwrap(store.conversations.first?.id)
        let assistantId = UUID()

        store.addMessage(ChatMessage(role: .user, content: "Hello"), to: conversationId)
        store.addMessage(
            ChatMessage(
                id: assistantId,
                role: .assistant,
                content: "Monolithic",
                primaryTextSnapshot: "Monolithic",
                blocks: [
                    PersistedChatTimelineBlock(
                        id: "primary-text",
                        kind: .primaryText,
                        text: "Monolithic",
                        sequence: 0
                    ),
                ],
                isStreaming: true
            ),
            to: conversationId
        )

        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantId,
            turnId: assistantId.uuidString,
            providerId: "codex-cli"
        )
        state.isStreaming = true
        state.orderedTextStreamIds = ["main"]
        state.textByStreamId = ["main": "Prima parteSeconda parte"]
        state.textSegments = ["Prima parte", "Seconda parte"]
        state.timelineSegments = [
            ChatTimelineSegment(kind: .text, index: 0, sequence: 0),
            ChatTimelineSegment(kind: .toolUse, index: 0, sequence: 1),
            ChatTimelineSegment(kind: .text, index: 1, sequence: 2),
        ]

        store.updateAssistantMessagePipelineState(
            messageId: assistantId,
            state: state,
            in: conversationId,
            persistImmediately: false
        )

        let conversation = try XCTUnwrap(store.conversation(for: conversationId))
        let message = try XCTUnwrap(conversation.messages.first(where: { $0.id == assistantId }))
        XCTAssertEqual(
            message.resolvedTimelineBlocks.map(\.kind),
            [.primaryText, .toolMarker, .primaryText]
        )
        XCTAssertEqual(
            message.resolvedTimelineBlocks.map(\.sequence),
            [0, 1, 2]
        )
        XCTAssertEqual(
            message.resolvedTimelineBlocks
                .filter { $0.kind == .primaryText }
                .map(\.text),
            ["Prima parte", "Seconda parte"]
        )
    }

    func testResolvedTimelineBlocksSanitizeDuplicateReasoningIDsFromPipelineState() {
        let conversationId = UUID()
        let assistantId = UUID()

        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantId,
            turnId: assistantId.uuidString,
            providerId: "codex-cli"
        )
        state.textSegments = ["Risposta"]
        state.textByStreamId = ["main": "Risposta"]
        state.orderedTextStreamIds = ["main"]
        state.reasoningByGroupId = ["reasoning": "Step 1\n\nStep 2"]
        state.timelineSegments = [
            ChatTimelineSegment(kind: .reasoning, index: 0, sequence: 0),
            ChatTimelineSegment(kind: .text, index: 0, sequence: 1),
            ChatTimelineSegment(kind: .reasoning, index: 0, sequence: 2),
        ]

        let ids = state.blocks.map(\.id)

        XCTAssertEqual(ids, ["reasoning", "text-seg-0", "reasoning__dup1-seq2"])
    }
}
