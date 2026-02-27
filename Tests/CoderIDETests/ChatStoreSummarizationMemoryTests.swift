import XCTest
import CoderEngine
@testable import CoderIDE

private struct SummarizationMockProvider: LLMProvider {
    let id: String = "mock-summary"
    let displayName: String = "Mock Summary"
    let response: String

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.textDelta(response))
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}

@MainActor
final class ChatStoreSummarizationMemoryTests: XCTestCase {
    private func makeStore() -> ChatStore {
        let suiteName = "ChatStoreSummarizationMemoryTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return ChatStore()
        }
        defaults.removePersistentDomain(forName: suiteName)
        return ChatStore(userDefaults: defaults)
    }

    func testSummarizeConversationStoresMemoryWithoutTrimmingVisibleMessages() async throws {
        let store = makeStore()
        guard let conversationId = store.conversations.first?.id else {
            return XCTFail("Missing initial conversation")
        }

        for idx in 0..<6 {
            let role: ChatMessage.Role = idx.isMultiple(of: 2) ? .user : .assistant
            store.addMessage(
                ChatMessage(role: role, content: "message \(idx)"),
                to: conversationId
            )
        }

        let beforeCount = store.conversation(for: conversationId)?.messages.count ?? 0
        let provider = SummarizationMockProvider(
            response: """
            ## Objectives
            Keep stable history.
            ## Decisions
            Use memory summary.
            ## Progress
            Added compact memory.
            ## Open items
            None.
            ## User preferences
            Italian responses.
            """
        )
        let ctx = WorkspaceContext(workspacePath: URL(fileURLWithPath: "/tmp"))

        let didSummarize = try await store.summarizeConversation(
            id: conversationId,
            keepLast: 3,
            provider: provider,
            context: ctx
        )

        XCTAssertTrue(didSummarize)
        guard let updated = store.conversation(for: conversationId) else {
            return XCTFail("Conversation missing after summarize")
        }
        XCTAssertEqual(updated.messages.count, beforeCount)
        XCTAssertEqual(updated.contextMemorySourceMessageCount, beforeCount)
        XCTAssertNotNil(updated.contextMemoryGeneratedAt)
        XCTAssertTrue(updated.contextMemorySummaryMarkdown?.contains("## Objectives") == true)
        XCTAssertTrue(updated.contextMemorySummaryMarkdown?.contains("Use memory summary.") == true)
    }
}
