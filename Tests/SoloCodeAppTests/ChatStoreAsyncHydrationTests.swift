import XCTest
@testable import CoderIDE

@MainActor
final class ChatStoreAsyncHydrationTests: XCTestCase {
    func testAsyncConversationHydrationDoesNotCreatePhantomDefaultThread() async throws {
        let suiteName = "ChatStoreAsyncHydrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let largeMessage = String(repeating: "A", count: ChatStore.asyncLoadThreshold + 5_000)
        let persistedConversation = Conversation(
            title: "Persisted",
            messages: [
                ChatMessage(role: .user, content: largeMessage)
            ],
            mode: .agent
        )
        let data = try JSONEncoder().encode([persistedConversation])
        defaults.set(data, forKey: "CoderIDE.conversations")

        let store = ChatStore(userDefaults: defaults)
        XCTAssertTrue(store.conversations.isEmpty || store.conversations.count == 1)

        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if store.conversations.contains(where: { $0.title == "Persisted" }) {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertEqual(store.conversations.first?.title, "Persisted")
        XCTAssertEqual(store.conversations.first?.messages.count, 1)
    }

    func testHydrationSettlesPersistedAssistantStreamingState() throws {
        let suiteName = "ChatStoreAsyncHydrationTests.streaming.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let persistedConversation = Conversation(
            title: "Persisted",
            messages: [
                ChatMessage(
                    role: .assistant,
                    content: "partial",
                    turnMetadata: ChatTurnMetadata(
                        turnId: "turn-1",
                        providerId: "codex-cli",
                        sequence: 1,
                        status: "streaming",
                        startedAt: Date(timeIntervalSince1970: 10),
                        completedAt: nil,
                        updatedAt: Date(timeIntervalSince1970: 12),
                        isStreaming: true
                    ),
                    isStreaming: true
                ),
            ],
            mode: .agent
        )
        let data = try JSONEncoder().encode([persistedConversation])
        defaults.set(data, forKey: "CoderIDE.conversations")

        let store = ChatStore(userDefaults: defaults)
        let message = try XCTUnwrap(store.conversations.first?.messages.first)

        XCTAssertFalse(message.isStreaming)
        XCTAssertEqual(message.turnMetadata?.status, "completed")
        XCTAssertFalse(message.turnMetadata?.isStreaming ?? true)
    }
}
