import XCTest
@testable import CoderIDE

@MainActor
final class TodoRuntimeFollowUpInsertionPolicyTests: XCTestCase {
    func testImplicitFollowUpsStayDisabledForRuntimeImplementationTodos() {
        let suiteName = "TodoRuntimeFollowUpInsertionPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = TodoStore(
            storageKey: "CoderIDE.todos.tests.\(UUID().uuidString)",
            userDefaults: defaults
        )
        let conversationId = UUID()

        store.upsertFromAgent(
            id: nil,
            title: "Implementare fix stream",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )

        XCTAssertEqual(
            TodoRuntimeFollowUpInsertionPolicy.implicitFollowUpTitles(
                in: store.todos,
                conversationId: conversationId
            ),
            []
        )
    }
}
