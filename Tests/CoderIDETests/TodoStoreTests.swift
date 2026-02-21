import XCTest
@testable import CoderIDE

@MainActor
final class TodoStoreTests: XCTestCase {
    private let storageKey = "CoderIDE.todos"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        super.tearDown()
    }

    func testClearAgentTodosPreservesManualItems() {
        let store = TodoStore()
        store.add(title: "Manual A", source: .manual)
        store.add(title: "Agent A", source: .agent)
        store.add(title: "Manual B", source: .manual)

        store.clearAgentTodos()

        XCTAssertEqual(store.todos.count, 2)
        XCTAssertTrue(store.todos.allSatisfy { $0.source == .manual })
        XCTAssertEqual(store.todos.map(\.title).sorted(), ["Manual A", "Manual B"])
    }
}
