import XCTest
@testable import CoderIDE

@MainActor
final class TodoChatDisplayPolicyTests: XCTestCase {
    func testPolicyShowsManualAlongsideScopedInSameChat() {
        let conv = UUID()
        let manual = TodoItem(title: "Manual note", source: .manual)
        let scoped = TodoItem(
            title: "Scoped agent",
            source: .agent,
            planConversationId: conv
        )
        let visible = [manual, scoped]
        XCTAssertTrue(
            TodoChatDisplayPolicy.itemAppearsInChat(manual, conversationId: conv, visibleTodos: visible)
        )
    }

    func testPolicyAnchorsAgentOrphanToLexicographicallySmallestScopedThread() {
        let convA = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let convB = UUID(uuidString: "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let orphan = TodoItem(title: "Orphan", source: .agent, planConversationId: nil)
        let scopedA = TodoItem(title: "A", source: .agent, planConversationId: convA)
        let scopedB = TodoItem(title: "B", source: .agent, planConversationId: convB)
        let visible = [orphan, scopedA, scopedB]
        XCTAssertTrue(
            TodoChatDisplayPolicy.itemAppearsInChat(orphan, conversationId: convA, visibleTodos: visible)
        )
        XCTAssertFalse(
            TodoChatDisplayPolicy.itemAppearsInChat(orphan, conversationId: convB, visibleTodos: visible)
        )
    }

    func testPolicyHidesManualWhenChatOnlySeesForeignScopedWorld() {
        let convA = UUID()
        let convB = UUID()
        let manual = TodoItem(title: "Orphan manual", source: .manual)
        let foreignScoped = TodoItem(
            title: "Other thread",
            source: .agent,
            planConversationId: convA
        )
        let visible = [manual, foreignScoped]
        XCTAssertTrue(
            TodoChatDisplayPolicy.itemAppearsInChat(manual, conversationId: convA, visibleTodos: visible)
        )
        XCTAssertFalse(
            TodoChatDisplayPolicy.itemAppearsInChat(manual, conversationId: convB, visibleTodos: visible)
        )
    }

    func testPolicyMatchesTodoStoreDisplayTodosForChat() {
        let storageKey = "CoderIDE.todos.policy.\(UUID().uuidString)"
        let suiteName = "TodoChatDisplayPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = TodoStore(storageKey: storageKey, userDefaults: defaults)
        let conv = UUID()
        store.upsertFromAgent(
            id: nil,
            title: "Runtime",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conv
        )
        store.add(title: "User task", source: .manual)
        let expected = Set(store.displayTodosForChat(for: conv).map(\.id))
        let visible = store.userVisibleTodos
        let fromPolicy = Set(
            store.userVisibleTodos
                .filter { TodoChatDisplayPolicy.itemAppearsInChat($0, conversationId: conv, visibleTodos: visible) }
                .map(\.id)
        )
        XCTAssertEqual(fromPolicy, expected)
    }

    func testTodoConversationScopeFilterUsesPolicySemantics() {
        let convA = UUID()
        let convB = UUID()
        let manual = TodoItem(title: "Shared list item", source: .manual)
        let scopedA = TodoItem(title: "A work", source: .agent, planConversationId: convA)
        let todos = [manual, scopedA]
        let filterB = todoConversationScopeFilter(todos: todos, conversationId: convB)
        XCTAssertFalse(filterB(manual))
        let filterA = todoConversationScopeFilter(todos: todos, conversationId: convA)
        XCTAssertTrue(filterA(manual))
    }
}
