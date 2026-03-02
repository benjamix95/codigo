import XCTest
@testable import CoderIDE

@MainActor
final class ChatStoreStreamingTargetTests: XCTestCase {
    private let convKey = "CoderIDE.conversations"
    private let planKey = "CoderIDE.planBoards"

    override func setUp() {
        super.setUp()
        clearPersistedState()
    }

    override func tearDown() {
        clearPersistedState()
        super.tearDown()
    }

    func testUpdateLastAssistantMessageTargetsActiveStreamingAssistant() throws {
        let store = ChatStore()
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
        let store = ChatStore()
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
        let store = ChatStore()
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
    }

    func testRemoveTrailingEmptyAssistantMessages() throws {
        let store = ChatStore()
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
    }

    func testRemoveTrailingEmptyDoesNotRemoveStreamingMessage() throws {
        let store = ChatStore()
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

    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: convKey)
        UserDefaults.standard.removeObject(forKey: planKey)
    }
}
