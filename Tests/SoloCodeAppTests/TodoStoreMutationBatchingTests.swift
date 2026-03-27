import XCTest
@testable import CoderIDE

@MainActor
final class TodoStoreMutationBatchingTests: XCTestCase {
    func testBatchDefersPersistenceUntilBatchEnd() {
        let suiteName = "TodoStoreMutationBatchingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storageKey = "CoderIDE.todos.batch.\(UUID().uuidString)"
        let store = TodoStore(storageKey: storageKey, userDefaults: defaults)

        store.performBatchUpdates {
            store.add(title: "Manual task", source: .manual)
            XCTAssertNil(defaults.data(forKey: storageKey))

            store.upsertFromAgent(
                id: nil,
                title: "Agent task",
                status: .pending,
                priority: .medium,
                notes: nil,
                linkedFiles: [],
                conversationId: nil
            )
            XCTAssertNil(defaults.data(forKey: storageKey))
            XCTAssertTrue(store.needsSaveAfterBatch)
        }

        XCTAssertFalse(store.needsSaveAfterBatch)
        XCTAssertEqual(
            Set(store.displayTodosForChat(for: nil).map(\.title)),
            Set(["Manual task", "Agent task"])
        )
        XCTAssertNotNil(defaults.data(forKey: storageKey))
    }
}
