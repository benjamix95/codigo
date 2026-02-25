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

    func testUpsertCanonicalPlanTodosKeepsStableIdsForSameTitles() {
        let store = TodoStore()
        store.upsertCanonicalPlanTodos(["Step A", "Step B"])
        let firstIds = store.todos.filter { $0.isPlanCanonical }.map(\.id)

        store.upsertCanonicalPlanTodos(["Step A", "Step B"])
        let secondIds = store.todos.filter { $0.isPlanCanonical }.map(\.id)

        XCTAssertEqual(firstIds.count, 2)
        XCTAssertEqual(Set(firstIds), Set(secondIds))
    }

    func testRuntimeUpsertBindsToCanonicalTodo() {
        let store = TodoStore()
        store.upsertCanonicalPlanTodos(["Mappare flusso plan"])

        let canonicalBefore = store.todos.first { $0.isPlanCanonical }
        XCTAssertNotNil(canonicalBefore)

        store.upsertFromAgent(
            id: nil,
            title: "mappare   flusso PLAN",
            status: .inProgress,
            priority: .high,
            notes: "in corso",
            linkedFiles: []
        )

        let canonicalAfter = store.todos.first { $0.isPlanCanonical }
        XCTAssertEqual(store.todos.count, 1)
        XCTAssertEqual(canonicalBefore?.id, canonicalAfter?.id)
        XCTAssertEqual(canonicalAfter?.status, .inProgress)
        XCTAssertEqual(canonicalAfter?.priority, .high)
    }

    func testSortedCanonicalFirstTodosPrioritizesPlanTodos() {
        let store = TodoStore()
        store.add(title: "Runtime task", source: .agent, priority: .high)
        store.upsertCanonicalPlanTodos(["Plan task"])

        let sorted = store.sortedCanonicalFirstTodos()
        XCTAssertEqual(sorted.first?.title, "Plan task")
        XCTAssertTrue(sorted.first?.isPlanCanonical == true)
    }

    func testClearAgentTodosPreservesCanonicalPlanTodos() {
        let store = TodoStore()
        store.upsertCanonicalPlanTodos(["Plan A"])
        store.add(title: "Runtime A", source: .agent)

        store.clearAgentTodos()

        XCTAssertEqual(store.todos.count, 1)
        XCTAssertEqual(store.todos.first?.title, "Plan A")
        XCTAssertTrue(store.todos.first?.isPlanCanonical == true)
    }

    func testClearAgentTodosWithIncludePlanCanonicalRemovesAllAgentTodos() {
        let store = TodoStore()
        store.upsertCanonicalPlanTodos(["Plan A"])
        store.add(title: "Runtime A", source: .agent)
        store.add(title: "Manual A", source: .manual)

        store.clearAgentTodos(includePlanCanonical: true)

        XCTAssertEqual(store.todos.count, 1)
        XCTAssertEqual(store.todos.first?.title, "Manual A")
        XCTAssertEqual(store.todos.first?.source, .manual)
    }

    func testRemovedCanonicalTasksBecomeBlockedWithStandardNote() {
        let store = TodoStore()
        store.upsertCanonicalPlanTodos(["Task 1", "Task 2"])
        store.upsertCanonicalPlanTodos(["Task 1"])

        let removed = store.todos.first { $0.title == "Task 2" }
        XCTAssertEqual(removed?.status, .blocked)
        XCTAssertEqual(removed?.notes, "Removed from current plan")
    }

    func testEmptyPlanTodosBlocksPendingCanonicalTasks() {
        let store = TodoStore()
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
        let store = TodoStore()
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
        let store = TodoStore()
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
        let store = TodoStore()
        store.upsertCanonicalPlanTodos(["Implementare parser wizard"])

        let updated = store.upsertCanonicalOnlyFromAgent(
            id: nil,
            title: "implementare   parser WIZARD",
            status: .inProgress,
            priority: .high,
            notes: "in corso",
            linkedFiles: ["Sources/CoderIDE/PlanOptionsParser.swift"]
        )

        XCTAssertTrue(updated)
        XCTAssertEqual(store.todos.count, 1)
        XCTAssertEqual(store.todos.first?.isPlanCanonical, true)
        XCTAssertEqual(store.todos.first?.status, .inProgress)
        XCTAssertEqual(store.todos.first?.priority, .high)
    }

    func testUpsertCanonicalOnlyFromAgentIgnoresUnknownRuntimeTodo() {
        let store = TodoStore()
        store.upsertCanonicalPlanTodos(["Task canonica"])

        let updated = store.upsertCanonicalOnlyFromAgent(
            id: nil,
            title: "Task runtime non canonica",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: []
        )

        XCTAssertFalse(updated)
        XCTAssertEqual(store.todos.count, 1)
        XCTAssertEqual(store.todos.first?.title, "Task canonica")
    }
}
