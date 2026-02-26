import XCTest
@testable import CoderIDE

@MainActor
final class TodoStoreTests: XCTestCase {
    private var storageKey: String!
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        storageKey = "CoderIDE.todos.tests.\(UUID().uuidString)"
        suiteName = "TodoStoreTests.\(UUID().uuidString)"
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

    func testClearAgentTodosPreservesManualItems() {
        let store = makeStore()
        store.add(title: "Manual A", source: .manual)
        store.add(title: "Agent A", source: .agent)
        store.add(title: "Manual B", source: .manual)

        store.clearAgentTodos()

        XCTAssertEqual(store.todos.count, 2)
        XCTAssertTrue(store.todos.allSatisfy { $0.source == .manual })
        XCTAssertEqual(store.todos.map(\.title).sorted(), ["Manual A", "Manual B"])
    }

    func testUpsertCanonicalPlanTodosKeepsStableIdsForSameTitles() {
        let store = makeStore()
        store.upsertCanonicalPlanTodos(["Step A", "Step B"])
        let firstIds = store.todos.filter { $0.isPlanCanonical }.map(\.id)

        store.upsertCanonicalPlanTodos(["Step A", "Step B"])
        let secondIds = store.todos.filter { $0.isPlanCanonical }.map(\.id)

        XCTAssertEqual(firstIds.count, 2)
        XCTAssertEqual(Set(firstIds), Set(secondIds))
    }

    func testRuntimeUpsertBindsToCanonicalTodo() {
        let store = makeStore()
        store.upsertCanonicalPlanTodos(["Map plan flow"])

        let canonicalBefore = store.todos.first { $0.isPlanCanonical }
        XCTAssertNotNil(canonicalBefore)

        store.upsertFromAgent(
            id: nil,
            title: "map   plan FLOW",
            status: .inProgress,
            priority: .high,
            notes: "in progress",
            linkedFiles: []
        )

        let canonicalAfter = store.todos.first { $0.isPlanCanonical }
        XCTAssertEqual(store.todos.count, 1)
        XCTAssertEqual(canonicalBefore?.id, canonicalAfter?.id)
        XCTAssertEqual(canonicalAfter?.status, .inProgress)
        XCTAssertEqual(canonicalAfter?.priority, .high)
    }

    func testSortedCanonicalFirstTodosPrioritizesPlanTodos() {
        let store = makeStore()
        store.add(title: "Runtime task", source: .agent, priority: .high)
        store.upsertCanonicalPlanTodos(["Plan task"])

        let sorted = store.sortedCanonicalFirstTodos()
        XCTAssertEqual(sorted.first?.title, "Plan task")
        XCTAssertTrue(sorted.first?.isPlanCanonical == true)
    }

    func testClearAgentTodosPreservesCanonicalPlanTodos() {
        let store = makeStore()
        store.upsertCanonicalPlanTodos(["Plan A"])
        store.add(title: "Runtime A", source: .agent)

        store.clearAgentTodos()

        XCTAssertEqual(store.todos.count, 1)
        XCTAssertEqual(store.todos.first?.title, "Plan A")
        XCTAssertTrue(store.todos.first?.isPlanCanonical == true)
    }

    func testClearAgentTodosWithIncludePlanCanonicalRemovesAllAgentTodos() {
        let store = makeStore()
        store.upsertCanonicalPlanTodos(["Plan A"])
        store.add(title: "Runtime A", source: .agent)
        store.add(title: "Manual A", source: .manual)

        store.clearAgentTodos(includePlanCanonical: true)

        XCTAssertEqual(store.todos.count, 1)
        XCTAssertEqual(store.todos.first?.title, "Manual A")
        XCTAssertEqual(store.todos.first?.source, .manual)
    }

    func testRemovedCanonicalTasksBecomeBlockedWithStandardNote() {
        let store = makeStore()
        store.upsertCanonicalPlanTodos(["Task 1", "Task 2"])
        store.upsertCanonicalPlanTodos(["Task 1"])

        let removed = store.todos.first { $0.title == "Task 2" }
        XCTAssertEqual(removed?.status, .blocked)
        XCTAssertEqual(removed?.notes, "Removed from current plan")
    }

    func testEmptyPlanTodosBlocksPendingCanonicalTasks() {
        let store = makeStore()
        store.upsertCanonicalPlanTodos(["Task 1", "Task 2"])
        store.upsertFromAgent(
            id: nil,
            title: "Task 1",
            status: .done,
            priority: .medium,
            notes: nil,
            linkedFiles: []
        )

        store.upsertCanonicalPlanTodos([])

        let doneTask = store.todos.first { $0.isPlanCanonical && $0.title == "Task 1" }
        let removedTask = store.todos.first { $0.isPlanCanonical && $0.title == "Task 2" }
        XCTAssertEqual(doneTask?.status, .done)
        XCTAssertEqual(removedTask?.status, .blocked)
        XCTAssertEqual(removedTask?.notes, "Removed from current plan")
    }

    func testRuntimeExtraTaskStaysNonCanonical() {
        let store = makeStore()
        store.upsertCanonicalPlanTodos(["Task canonica lunga"])

        store.upsertFromAgent(
            id: nil,
            title: "Task runtime extra non correlata",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: []
        )

        let runtime = store.todos.first { $0.title == "Task runtime extra non correlata" }
        XCTAssertNotNil(runtime)
        XCTAssertEqual(runtime?.isPlanCanonical, false)
    }

    func testUpsertCanonicalPlanTodosDoesNotPromoteManualTodoWithSameTitle() {
        let store = makeStore()
        store.add(title: "Setup CI", source: .manual, priority: .high)

        store.upsertCanonicalPlanTodos(["Setup CI"])

        XCTAssertEqual(store.todos.count, 2)
        let manual = store.todos.first { $0.source == .manual }
        let canonical = store.todos.first { $0.isPlanCanonical }
        XCTAssertNotNil(manual)
        XCTAssertNotNil(canonical)
        XCTAssertEqual(manual?.title, "Setup CI")
        XCTAssertEqual(manual?.isPlanCanonical, false)
    }

    func testUpsertCanonicalOnlyFromAgentUpdatesExistingCanonicalTodo() {
        let store = makeStore()
        store.upsertCanonicalPlanTodos(["Implement parser wizard"])

        let updated = store.upsertCanonicalOnlyFromAgent(
            id: nil,
            title: "implement   parser WIZARD",
            status: .inProgress,
            priority: .high,
            notes: "in progress",
            linkedFiles: ["Sources/CoderIDE/PlanOptionsParser.swift"]
        )

        XCTAssertTrue(updated)
        XCTAssertEqual(store.todos.count, 1)
        XCTAssertEqual(store.todos.first?.isPlanCanonical, true)
        XCTAssertEqual(store.todos.first?.status, .inProgress)
        XCTAssertEqual(store.todos.first?.priority, .high)
    }

    func testUpsertCanonicalOnlyFromAgentIgnoresUnknownRuntimeTodo() {
        let store = makeStore()
        store.upsertCanonicalPlanTodos(["Canonical task"])

        let updated = store.upsertCanonicalOnlyFromAgent(
            id: nil,
            title: "Non-canonical runtime task",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: []
        )

        XCTAssertFalse(updated)
        XCTAssertEqual(store.todos.count, 1)
        XCTAssertEqual(store.todos.first?.title, "Canonical task")
    }
}
