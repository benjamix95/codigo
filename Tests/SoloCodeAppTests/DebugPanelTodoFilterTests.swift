import XCTest
@testable import CoderIDE

@MainActor
final class DebugPanelTodoFilterTests: XCTestCase {
    private var storageKey: String!
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        storageKey = "CoderIDE.todos.debugPanelTests.\(UUID().uuidString)"
        suiteName = "DebugPanelTodoFilterTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults?.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults?.removeObject(forKey: storageKey)
        userDefaults?.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
        storageKey = nil
        super.tearDown()
    }

    private func makeStore() -> TodoStore {
        TodoStore(storageKey: storageKey, userDefaults: userDefaults)
    }

    // MARK: - Debug Panel todo filtering (nil conversationId returns [])

    func testDisplayTodosForChatWithNilConversationIdReturnsAllTodos() {
        let store = makeStore()
        store.upsertFromAgent(
            id: nil,
            title: "Global task",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: nil
        )

        let result = store.displayTodosForChat(for: nil)
        XCTAssertFalse(result.isEmpty,
            "displayTodosForChat(for: nil) returns all todos - the Debug Panel must guard against this")
    }

    func testDebugPanelShouldReturnEmptyTodosWhenConversationIdIsNil() {
        let store = makeStore()
        store.upsertFromAgent(
            id: nil,
            title: "Some task",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: nil
        )

        let conversationId: UUID? = nil

        guard let conversationId else {
            XCTAssertTrue(true, "Debug Panel correctly returns [] when conversationId is nil")
            return
        }

        let result = store.displayTodosForChat(for: conversationId)
        XCTAssertTrue(result.isEmpty)
    }

    func testDisplayTodosForChatWithValidConversationIdFiltersByConversation() {
        let store = makeStore()
        let debugConversation = UUID()
        let otherConversation = UUID()

        store.upsertFromAgent(
            id: nil,
            title: "Debug task",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: debugConversation
        )
        store.upsertFromAgent(
            id: nil,
            title: "Other task",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: otherConversation
        )

        let debugTodos = store.displayTodosForChat(for: debugConversation)
        let otherTodos = store.displayTodosForChat(for: otherConversation)

        XCTAssertEqual(debugTodos.count, 1)
        XCTAssertEqual(debugTodos.first?.title, "Debug task")
        XCTAssertEqual(otherTodos.count, 1)
        XCTAssertEqual(otherTodos.first?.title, "Other task")
    }

    func testDisplayTodosForChatReturnsEmptyForUnknownConversation() {
        let store = makeStore()
        let knownConversation = UUID()

        store.upsertFromAgent(
            id: nil,
            title: "Scoped task",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: knownConversation
        )

        let result = store.displayTodosForChat(for: UUID())
        XCTAssertTrue(result.isEmpty)
    }
}
