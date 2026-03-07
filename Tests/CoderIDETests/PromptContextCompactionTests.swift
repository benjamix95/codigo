import XCTest
@testable import CoderIDE

@MainActor
final class PromptContextCompactionTests: XCTestCase {
    private func makeStore() -> ChatStore {
        let suiteName = "PromptContextCompactionTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return ChatStore()
        }
        defaults.removePersistentDomain(forName: suiteName)
        return ChatStore(userDefaults: defaults)
    }

    func testBuildPromptContextExcludesMemoryByDefaultAndKeepsRecentTail() {
        let store = makeStore()
        guard let conversationId = store.conversations.first?.id,
              let idx = store.conversations.firstIndex(where: { $0.id == conversationId }) else {
            return XCTFail("Missing initial conversation")
        }

        store.conversations[idx].contextMemorySummaryMarkdown = """
        ## Objectives
        Keep all visible chat messages.
        """

        store.addMessage(ChatMessage(role: .user, content: "old-message-1"), to: conversationId)
        store.addMessage(ChatMessage(role: .assistant, content: "old-message-2"), to: conversationId)
        store.addMessage(ChatMessage(role: .user, content: "recent-message-1"), to: conversationId)
        store.addMessage(ChatMessage(role: .assistant, content: "recent-message-2"), to: conversationId)

        let context = store.buildPromptContext(
            conversationId: conversationId,
            maxMessages: 2,
            maxCharsPerMessage: 200,
            includeMemorySummary: false
        )

        XCTAssertFalse(context.contains("### Conversation memory"))
        XCTAssertFalse(context.contains("Keep all visible chat messages."))
        XCTAssertFalse(context.contains("old-message-1"))
        XCTAssertFalse(context.contains("old-message-2"))
        XCTAssertTrue(context.contains("recent-message-1"))
        XCTAssertTrue(context.contains("recent-message-2"))
    }

    func testBuildPromptContextCanIncludeMemoryWhenExplicitlyEnabled() {
        let store = makeStore()
        guard let conversationId = store.conversations.first?.id,
              let idx = store.conversations.firstIndex(where: { $0.id == conversationId }) else {
            return XCTFail("Missing initial conversation")
        }

        store.conversations[idx].contextMemorySummaryMarkdown = "## Objectives\nRemember this summary."

        let context = store.buildPromptContext(
            conversationId: conversationId,
            includeMemorySummary: true
        )

        XCTAssertTrue(context.contains("### Conversation memory"))
        XCTAssertTrue(context.contains("Remember this summary."))
    }
}
