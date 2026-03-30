import XCTest
@testable import CoderIDE

final class ChatTaskActivitySnapshotRefreshPolicyTests: XCTestCase {
    func testPrefersSelectedStoreConversationOverSnapshot() {
        let conversationId = UUID()
        let snapshotConversation = Conversation(
            id: conversationId,
            title: "Snapshot",
            messages: [ChatMessage(role: .assistant, content: "old")]
        )
        let storeConversation = Conversation(
            id: conversationId,
            title: "Store",
            messages: [
                ChatMessage(role: .assistant, content: "old"),
                ChatMessage(role: .assistant, content: "new")
            ]
        )

        let resolved = preferredConversationForTaskActivityDependentRefresh(
            selectedConversationId: conversationId,
            storeConversation: storeConversation,
            snapshotConversation: snapshotConversation
        )

        XCTAssertEqual(resolved?.title, "Store")
        XCTAssertEqual(resolved?.messages.count, 2)
    }

    func testFallsBackToSnapshotWhenStoreConversationIsUnavailable() {
        let conversationId = UUID()
        let snapshotConversation = Conversation(
            id: conversationId,
            title: "Snapshot",
            messages: [ChatMessage(role: .assistant, content: "cached")]
        )

        let resolved = preferredConversationForTaskActivityDependentRefresh(
            selectedConversationId: conversationId,
            storeConversation: nil,
            snapshotConversation: snapshotConversation
        )

        XCTAssertEqual(resolved?.title, "Snapshot")
        XCTAssertEqual(resolved?.messages.count, 1)
    }

    func testIgnoresConversationsFromDifferentThread() {
        let selectedConversationId = UUID()
        let otherConversation = Conversation(
            id: UUID(),
            title: "Other",
            messages: [ChatMessage(role: .assistant, content: "other")]
        )

        let resolved = preferredConversationForTaskActivityDependentRefresh(
            selectedConversationId: selectedConversationId,
            storeConversation: otherConversation,
            snapshotConversation: otherConversation
        )

        XCTAssertNil(resolved)
    }
}
