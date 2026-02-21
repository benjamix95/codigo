import XCTest
@testable import CoderIDE

@MainActor
final class ChatStoreTaskOwnershipTests: XCTestCase {
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

    func testBeginTaskTracksConversationId() throws {
        let store = ChatStore()
        let convId = try XCTUnwrap(store.conversations.first?.id)

        store.beginTask(conversationId: convId)

        XCTAssertTrue(store.isLoading)
        XCTAssertEqual(store.activeTaskConversationId, convId)
        XCTAssertNotNil(store.taskStartDate)
    }

    func testEndTaskClearsOnlyMatchingConversationId() throws {
        let store = ChatStore()
        let convA = try XCTUnwrap(store.conversations.first?.id)
        let convB = store.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)

        store.beginTask(conversationId: convA)
        store.endTask(conversationId: convB)

        XCTAssertTrue(store.isLoading)
        XCTAssertEqual(store.activeTaskConversationId, convA)

        store.endTask(conversationId: convA)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.activeTaskConversationId)
    }

    func testCreateConversationAlwaysReturnsNewId() {
        let store = ChatStore()
        let id1 = store.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)
        let id2 = store.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)

        XCTAssertNotEqual(id1, id2)
    }

    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: convKey)
        UserDefaults.standard.removeObject(forKey: planKey)
    }
}
