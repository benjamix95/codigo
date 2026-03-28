import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class ChatStoreStreamingTargetTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName = ""

    override func setUpWithError() throws {
        suiteName = "ChatStoreStreamingTargetTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        userDefaults?.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = ""
    }

    func testUpdateLastAssistantMessageTargetsActiveStreamingAssistant() throws {
        let store = makeStore()
        let conversationId = try XCTUnwrap(store.conversations.first?.id)

        let streamingAssistantId = UUID()
        store.addMessage(ChatMessage(role: .user, content: "Hello"), to: conversationId)
        store.addMessage(
            ChatMessage(
                id: streamingAssistantId,
                role: .assistant,
                content: "",
                isStreaming: true
            ),
            to: conversationId
        )
        store.addMessage(
            ChatMessage(
                role: .assistant,
                content: "Reasoning message",
                isStreaming: false
            ),
            to: conversationId
        )

        store.updateLastAssistantMessage(
            content: "Final response",
            in: conversationId,
            persistImmediately: false
        )

        let conversation = try XCTUnwrap(store.conversation(for: conversationId))
        XCTAssertEqual(
            conversation.messages.first(where: { $0.id == streamingAssistantId })?.content,
            "Final response"
        )
        XCTAssertEqual(conversation.messages.last?.content, "Reasoning message")
    }

    func testSetLastAssistantStreamingTargetsActiveStreamingAssistant() throws {
        let store = makeStore()
        let conversationId = try XCTUnwrap(store.conversations.first?.id)

        let streamingAssistantId = UUID()
        store.addMessage(ChatMessage(role: .user, content: "Hello"), to: conversationId)
        store.addMessage(
            ChatMessage(
                id: streamingAssistantId,
                role: .assistant,
                content: "",
                isStreaming: true
            ),
            to: conversationId
        )
        store.addMessage(
            ChatMessage(
                role: .assistant,
                content: "Reasoning message",
                isStreaming: false
            ),
            to: conversationId
        )

        store.setLastAssistantStreaming(false, in: conversationId)

        let conversation = try XCTUnwrap(store.conversation(for: conversationId))
        XCTAssertEqual(
            conversation.messages.first(where: { $0.id == streamingAssistantId })?.isStreaming,
            false
        )
        XCTAssertEqual(conversation.messages.last?.isStreaming, false)
    }

    func testInsertMessagePlacesEntryBeforeAnchorMessage() throws {
        let store = makeStore()
        let conversationId = try XCTUnwrap(store.conversations.first?.id)

        let streamingAssistantId = UUID()
        let reasoningMessageId = UUID()

        store.addMessage(ChatMessage(role: .user, content: "Hello"), to: conversationId)
        store.addMessage(
            ChatMessage(
                id: streamingAssistantId,
                role: .assistant,
                content: "",
                isStreaming: true
            ),
            to: conversationId
        )
        store.insertMessage(
            ChatMessage(
                id: reasoningMessageId,
                role: .assistant,
                content: "Thinking block",
                isStreaming: false
            ),
            before: streamingAssistantId,
            in: conversationId
        )

        let conversation = try XCTUnwrap(store.conversation(for: conversationId))
        let ids = conversation.messages.map(\.id)
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(ids[1], reasoningMessageId)
        XCTAssertEqual(ids[2], streamingAssistantId)
        XCTAssertFalse(conversation.messages[1].isStreaming)
        XCTAssertTrue(conversation.messages[2].isStreaming)
    }

    func testAddMessageUpdatesNewConversationTitleFromFirstUserMessage() throws {
        let store = makeStore()
        let conversationId = try XCTUnwrap(store.conversations.first?.id)

        store.addMessage(ChatMessage(role: .user, content: "Hello from rust store"), to: conversationId)

        let conversation = try XCTUnwrap(store.conversation(for: conversationId))
        XCTAssertEqual(conversation.title, "Hello from rust store")
    }

    func testAddMessageFallsBackWhenRustStoreBridgeIsUnavailable() throws {
        let original = getenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT").map { String(cString: $0) }
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        defer {
            if let original {
                setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", original, 1)
            } else {
                unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
            }
        }

        let store = makeStore()
        let conversationId = try XCTUnwrap(store.conversations.first?.id)

        store.addMessage(ChatMessage(role: .user, content: "Messaggio visibile"), to: conversationId)
        store.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true),
            to: conversationId
        )

        let conversation = try XCTUnwrap(store.conversation(for: conversationId))
        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.messages.first?.content, "Messaggio visibile")
        XCTAssertTrue(conversation.messages.last?.isStreaming ?? false)
        XCTAssertEqual(conversation.title, "Messaggio visibile")
    }

    func testUpdateLastAssistantMessageFallsBackWhenRustStoreBridgeIsUnavailable() throws {
        let original = getenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT").map { String(cString: $0) }
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        defer {
            if let original {
                setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", original, 1)
            } else {
                unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
            }
        }

        let store = makeStore()
        let conversationId = try XCTUnwrap(store.conversations.first?.id)

        store.addMessage(ChatMessage(role: .user, content: "Prompt"), to: conversationId)
        store.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true),
            to: conversationId
        )

        store.updateLastAssistantMessage(
            content: "Risposta aggiornata",
            in: conversationId,
            persistImmediately: false
        )

        let conversation = try XCTUnwrap(store.conversation(for: conversationId))
        XCTAssertEqual(conversation.messages.last?.content, "Risposta aggiornata")
    }

    func testPipelineStatePreservesVisibleTextWhenRustCommitHasOnlyArtifacts() throws {
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

        let store = makeStore()
        let conversationId = try XCTUnwrap(store.conversations.first?.id)
        let assistantId = UUID()

        store.addMessage(ChatMessage(role: .user, content: "Hello"), to: conversationId)
        store.addMessage(
            ChatMessage(
                id: assistantId,
                role: .assistant,
                content: "Visible answer",
                primaryTextSnapshot: "Visible answer",
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
        state.isStreaming = false
        state.artifacts = [
            ChatArtifact(
                id: "status-1",
                kind: .status,
                title: "Status",
                text: "Completed"
            )
        ]

        store.updateAssistantMessagePipelineState(
            messageId: assistantId,
            state: state,
            in: conversationId,
            persistImmediately: false
        )

        let conversation = try XCTUnwrap(store.conversation(for: conversationId))
        let message = try XCTUnwrap(conversation.messages.first(where: { $0.id == assistantId }))
        XCTAssertEqual(message.primaryTextSnapshot, "Visible answer")
        XCTAssertEqual(message.content, "Visible answer")
        XCTAssertTrue(message.resolvedTimelineBlocks.contains(where: { $0.kind == .status }))
        XCTAssertEqual(message.resolvedTimelineBlocks.first?.kind, .primaryText)
        XCTAssertEqual(message.resolvedTimelineBlocks.first?.text, "Visible answer")
    }

    /// Quando `sync_assistant_pipeline_state` ha successo, il round-trip Rust poteva lasciare il
    /// messaggio in RAM senza i `toolMarker` appena prodotti da `ChatTurnState.blocks`.
    func testPipelineCommitPropagatesToolMarkersWhenRustApplySucceeds() throws {
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

        let store = makeStore()
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
        state.textByStreamId = ["main": "AB"]
        state.textSegments = ["A", "B"]
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
        let markers = (message.blocks ?? []).filter { $0.kind == .toolMarker }.count
        XCTAssertGreaterThan(markers, 0)
    }

    func testPipelineCommitPreservesLocalAssistantMetadataWhenRustApplySucceeds() throws {
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

        let store = makeStore()
        let conversationId = try XCTUnwrap(store.conversations.first?.id)
        let assistantId = UUID()
        let expectedAttachment = ChatAttachment(
            kind: .document,
            originalName: "notes.md",
            localPath: "/tmp/notes.md"
        )
        let expectedPlanAttachment = PlanAttachment(
            historyEntryId: UUID(),
            layoutVersion: 2,
            showExpand: true,
            snapshotTitle: "Plan snapshot"
        )
        let expectedCard = SubagentCardSnapshot(
            swarmId: "swarm-1",
            status: .running,
            title: "Worker",
            detail: "Collecting output",
            summary: "Partial summary",
            errorCount: 0,
            warningCount: 1,
            resultPreview: "Preview",
            transcript: nil
        )

        store.addMessage(ChatMessage(role: .user, content: "Hello"), to: conversationId)
        let assistantMessage = ChatMessage(
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
        )
        store.addMessage(assistantMessage, to: conversationId)
        let conversationIndex = try XCTUnwrap(store.conversations.firstIndex(where: { $0.id == conversationId }))
        let messageIndex = try XCTUnwrap(
            store.conversations[conversationIndex].messages.firstIndex(where: { $0.id == assistantId })
        )
        store.conversations[conversationIndex].messages[messageIndex].attachments = [expectedAttachment]
        store.conversations[conversationIndex].messages[messageIndex].planAttachment = expectedPlanAttachment
        store.conversations[conversationIndex].messages[messageIndex].reasoningText = "Existing reasoning"
        store.conversations[conversationIndex].messages[messageIndex].subagentCards = [expectedCard]

        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantId,
            turnId: assistantId.uuidString,
            providerId: "codex-cli"
        )
        state.isStreaming = false
        state.orderedTextStreamIds = ["main"]
        state.textByStreamId = ["main": "Updated answer"]
        state.textSegments = ["Updated answer"]
        state.timelineSegments = [
            ChatTimelineSegment(kind: .text, index: 0, sequence: 0),
        ]

        store.updateAssistantMessagePipelineState(
            messageId: assistantId,
            state: state,
            in: conversationId,
            persistImmediately: false
        )

        let conversation = try XCTUnwrap(store.conversation(for: conversationId))
        let message = try XCTUnwrap(conversation.messages.first(where: { $0.id == assistantId }))
        XCTAssertEqual(message.primaryTextSnapshot, "Updated answer")
        XCTAssertEqual(message.content, "Updated answer")
        XCTAssertEqual(message.attachments, [expectedAttachment])
        XCTAssertEqual(message.planAttachment, expectedPlanAttachment)
        XCTAssertEqual(message.reasoningText, "Existing reasoning")
        XCTAssertEqual(message.subagentCards, [expectedCard])
    }

    func testRemoveTrailingEmptyAssistantMessages() async throws {
        let store = makeStore()
        let conversationId = try XCTUnwrap(store.conversations.first?.id)

        store.addMessage(ChatMessage(role: .user, content: "Hello"), to: conversationId)
        store.addMessage(
            ChatMessage(role: .assistant, content: "Turn 1 response", isStreaming: false),
            to: conversationId
        )
        store.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: false),
            to: conversationId
        )
        store.addMessage(
            ChatMessage(role: .assistant, content: "  \n  ", isStreaming: false),
            to: conversationId
        )

        let before = try XCTUnwrap(store.conversation(for: conversationId))
        XCTAssertEqual(before.messages.count, 4)

        store.removeTrailingEmptyAssistantMessages(in: conversationId)

        let after = try XCTUnwrap(store.conversation(for: conversationId))
        XCTAssertEqual(after.messages.count, 2)
        XCTAssertEqual(after.messages.last?.content, "Turn 1 response")

        try? await Task.sleep(nanoseconds: 350_000_000)
        let reloadedStore = makeStore()
        let reloadedConversation = try XCTUnwrap(reloadedStore.conversation(for: conversationId))
        XCTAssertEqual(reloadedConversation.messages.count, 2)
        XCTAssertEqual(reloadedConversation.messages.last?.content, "Turn 1 response")
    }

    func testRemoveTrailingEmptyDoesNotRemoveStreamingMessage() throws {
        let store = makeStore()
        let conversationId = try XCTUnwrap(store.conversations.first?.id)

        store.addMessage(ChatMessage(role: .user, content: "Hello"), to: conversationId)
        store.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true),
            to: conversationId
        )

        store.removeTrailingEmptyAssistantMessages(in: conversationId)

        let after = try XCTUnwrap(store.conversation(for: conversationId))
        XCTAssertEqual(after.messages.count, 2)
        XCTAssertTrue(after.messages.last?.isStreaming ?? false)
    }

    private func makeStore() -> ChatStore {
        ChatStore(userDefaults: userDefaults)
    }
}
