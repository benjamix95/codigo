import XCTest
@testable import CoderIDE

final class ChatPanelFinalActionsVisibilityTests: XCTestCase {
    func testHiddenWhenConversationMissing() {
        XCTAssertFalse(
            ChatPanelView.shouldShowFinalChatActions(
                conversation: nil,
                isLoadingForCurrentConversation: false
            )
        )
    }

    func testHiddenWhenTaskIsRunning() {
        let conversation = Conversation(
            title: "Thread",
            messages: [ChatMessage(role: .assistant, content: "Done", isStreaming: false)]
        )

        XCTAssertFalse(
            ChatPanelView.shouldShowFinalChatActions(
                conversation: conversation,
                isLoadingForCurrentConversation: true
            )
        )
    }

    func testHiddenWhenNoAssistantMessagesExist() {
        let conversation = Conversation(
            title: "Thread",
            messages: [ChatMessage(role: .user, content: "Hi", isStreaming: false)]
        )

        XCTAssertFalse(
            ChatPanelView.shouldShowFinalChatActions(
                conversation: conversation,
                isLoadingForCurrentConversation: false
            )
        )
    }

    func testHiddenWhenLastAssistantMessageIsStreaming() {
        let conversation = Conversation(
            title: "Thread",
            messages: [ChatMessage(role: .assistant, content: "Thinking...", isStreaming: true)]
        )

        XCTAssertFalse(
            ChatPanelView.shouldShowFinalChatActions(
                conversation: conversation,
                isLoadingForCurrentConversation: false
            )
        )
    }

    func testVisibleWhenLastMessageIsFinalAssistant() {
        let conversation = Conversation(
            title: "Thread",
            messages: [
                ChatMessage(role: .user, content: "Prompt", isStreaming: false),
                ChatMessage(role: .assistant, content: "Final answer", isStreaming: false),
            ]
        )

        XCTAssertTrue(
            ChatPanelView.shouldShowFinalChatActions(
                conversation: conversation,
                isLoadingForCurrentConversation: false
            )
        )
    }

    func testHiddenWhenLastMessageIsUser() {
        let conversation = Conversation(
            title: "Thread",
            messages: [
                ChatMessage(role: .assistant, content: "Previous answer", isStreaming: false),
                ChatMessage(role: .user, content: "New prompt", isStreaming: false),
            ]
        )

        XCTAssertFalse(
            ChatPanelView.shouldShowFinalChatActions(
                conversation: conversation,
                isLoadingForCurrentConversation: false
            )
        )
    }
}
