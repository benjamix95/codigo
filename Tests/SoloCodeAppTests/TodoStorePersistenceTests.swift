import XCTest
@testable import CoderIDE

@MainActor
final class TodoStorePersistenceTests: XCTestCase {
    func testSaveTodosSkipsRedundantWriteWhenVisibleTodosAreUnchanged() throws {
        let suiteName = "TodoStorePersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TodoStore(
            storageKey: "CoderIDE.todos.tests.\(UUID().uuidString)",
            userDefaults: defaults
        )
        store.add(title: "Visible todo", source: .manual)
        let initialData = try XCTUnwrap(store.lastSavedVisibleTodosData)

        store.todos.append(
            TodoItem(
                title: "hidden",
                status: .pending,
                priority: .low,
                source: .agent,
                isOperationalPlaceholder: true
            )
        )
        store.saveTodos()

        XCTAssertEqual(store.lastSavedVisibleTodosData, initialData)
    }
}
