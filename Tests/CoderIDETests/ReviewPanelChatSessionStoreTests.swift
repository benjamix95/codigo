import XCTest
@testable import CoderIDE

@MainActor
final class ReviewPanelChatSessionStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReviewPanelChatSessionStore.shared.clearAll()
    }

    func testCreateSelectArchiveDeleteThreadLifecycle() {
        let key = "panel-chat-tests"
        let store = ReviewPanelChatSessionStore.shared

        let first = store.createThread(for: key, title: "First")
        store.appendMessage(
            ReviewPanelMessage(role: .user, content: "Hello there"),
            for: key
        )
        let second = store.createThread(for: key, title: "Second")
        store.appendMessage(
            ReviewPanelMessage(role: .assistant, content: "Another thread"),
            for: key
        )

        var conversation = store.conversation(for: key)
        XCTAssertEqual(conversation.activeThreadId, second)
        XCTAssertEqual(conversation.threads.count, 2)

        store.selectThread(first, for: key)
        conversation = store.conversation(for: key)
        XCTAssertEqual(conversation.activeThreadId, first)

        store.archiveThread(first, for: key)
        conversation = store.conversation(for: key)
        XCTAssertTrue(conversation.threads.first(where: { $0.id == first })?.archived == true)
        XCTAssertEqual(conversation.activeThreadId, second)

        store.restoreThread(first, for: key)
        conversation = store.conversation(for: key)
        XCTAssertFalse(conversation.threads.first(where: { $0.id == first })?.archived == true)

        store.deleteThread(second, for: key)
        conversation = store.conversation(for: key)
        XCTAssertEqual(conversation.threads.count, 1)
        XCTAssertEqual(conversation.threads.first?.id, first)
    }

    func testThreadSubtitleShowsLiveWhenProcessing() {
        let key = "panel-chat-live"
        let store = ReviewPanelChatSessionStore.shared

        _ = store.createThread(for: key, title: "Live Chat")
        store.setProcessing(true, startedAt: Date(), for: key)

        let conversation = store.conversation(for: key)
        XCTAssertEqual(conversation.threads.first?.subtitle, "Live")
    }

    func testCreateThreadUsesProvidedTitleAndSelectsIt() {
        let key = "panel-chat-custom-title"
        let store = ReviewPanelChatSessionStore.shared

        let threadId = store.createThread(for: key, title: "panel-123")
        let conversation = store.conversation(for: key)

        XCTAssertEqual(conversation.activeThreadId, threadId)
        XCTAssertEqual(conversation.threads.first?.title, "panel-123")
    }
}
