import XCTest
@testable import CoderIDE

@MainActor
final class TodoStoreCanonicalScopeTests: XCTestCase {
    private var storageKey: String!
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        storageKey = "CoderIDE.todos.tests.\(UUID().uuidString)"
        suiteName = "TodoStoreCanonicalScopeTests.\(UUID().uuidString)"
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

    func testCanonicalTodosDoesNotBleedLegacyUnscopedIntoForeignScopedConversation() {
        let store = makeStore()
        let scopedConversationId = UUID()
        let foreignConversationId = UUID()

        store.upsertCanonicalPlanTodos(["Legacy step"])
        store.upsertCanonicalPlanTodos(["Scoped step"], conversationId: scopedConversationId)

        XCTAssertEqual(store.canonicalTodos(for: scopedConversationId).map(\.title), ["Scoped step"])
        XCTAssertTrue(store.canonicalTodos(for: foreignConversationId).isEmpty)
    }

    func testCanonicalTodosStillFallsBackToLegacyWhenNoScopedPlanExists() {
        let store = makeStore()
        let conversationId = UUID()

        store.upsertCanonicalPlanTodos(["Legacy step"])

        XCTAssertEqual(store.canonicalTodos(for: conversationId).map(\.title), ["Legacy step"])
    }

    private func makeStore() -> TodoStore {
        TodoStore(storageKey: storageKey, userDefaults: userDefaults)
    }
}
