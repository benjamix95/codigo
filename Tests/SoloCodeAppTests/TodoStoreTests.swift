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

    func testUpsertCanonicalPlanTodosAssignsStablePlanOrder() {
        let store = makeStore()
        store.upsertCanonicalPlanTodos(["Step C", "Step A", "Step B"])

        let scoped = store.canonicalTodos(for: nil)
        XCTAssertEqual(scoped.map(\.title), ["Step C", "Step A", "Step B"])
        XCTAssertEqual(scoped.map(\.planOrder), [0, 1, 2])
    }

    func testPrepareCanonicalPlanTodosForBuildSetsFirstInProgressAndResetsOthers() {
        let store = makeStore()
        let conversationId = UUID()
        store.upsertCanonicalPlanTodos(["First", "Second", "Third"], conversationId: conversationId)

        store.upsertCanonicalOnlyFromAgent(
            id: nil,
            title: "First",
            status: .done,
            priority: nil,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )
        store.upsertCanonicalOnlyFromAgent(
            id: nil,
            title: "Second",
            status: .blocked,
            priority: nil,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )

        let prepared = store.prepareCanonicalPlanTodosForBuild(conversationId: conversationId)

        XCTAssertEqual(prepared.map(\.title), ["First", "Second", "Third"])
        XCTAssertEqual(prepared.map(\.status), [.done, .inProgress, .pending])
        XCTAssertEqual(prepared.first?.activeForm, "")
        XCTAssertEqual(prepared.dropFirst().first?.activeForm, "Second")
    }

    func testPrepareCanonicalPlanTodosForBuildFreshStartMarksFirstInProgress() {
        let store = makeStore()
        let conversationId = UUID()
        store.upsertCanonicalPlanTodos(["First", "Second", "Third"], conversationId: conversationId)

        let prepared = store.prepareCanonicalPlanTodosForBuild(conversationId: conversationId)

        XCTAssertEqual(prepared.map(\.status), [.inProgress, .pending, .pending])
        XCTAssertEqual(prepared.first?.activeForm, "First")
        XCTAssertTrue(prepared.dropFirst().allSatisfy { $0.activeForm.isEmpty })
    }

    func testPrepareCanonicalPlanTodosForBuildWhenAllDoneRestartsFromBeginning() {
        let store = makeStore()
        let conversationId = UUID()
        store.upsertCanonicalPlanTodos(["First", "Second", "Third"], conversationId: conversationId)
        for todo in store.canonicalTodos(for: conversationId) {
            store.setStatus(id: todo.id, status: .done)
        }

        let prepared = store.prepareCanonicalPlanTodosForBuild(conversationId: conversationId)

        XCTAssertEqual(prepared.map(\.status), [.inProgress, .pending, .pending])
    }

    func testUpsertCanonicalFromExecutionFallbackCompletesCurrentInProgressStep() {
        let store = makeStore()
        let conversationId = UUID()
        store.upsertCanonicalPlanTodos(["First", "Second"], conversationId: conversationId)
        _ = store.prepareCanonicalPlanTodosForBuild(conversationId: conversationId)

        let updated = store.upsertCanonicalFromExecutionFallback(
            status: .done,
            priority: nil,
            notes: "verified",
            activeForm: nil,
            linkedFiles: ["App/SoloCodeApp/Sources/Feature.swift"],
            conversationId: conversationId
        )

        XCTAssertTrue(updated)
        let canonical = store.canonicalTodos(for: conversationId)
        XCTAssertEqual(canonical.first?.status, .done)
        XCTAssertTrue(canonical.first?.linkedFiles.contains("App/SoloCodeApp/Sources/Feature.swift") == true)
    }

    func testAdvanceNextCanonicalTodoIfNeededStartsFirstPendingAfterDone() {
        let store = makeStore()
        let conversationId = UUID()
        store.upsertCanonicalPlanTodos(["First", "Second", "Third"], conversationId: conversationId)
        _ = store.prepareCanonicalPlanTodosForBuild(conversationId: conversationId)
        let canonical = store.canonicalTodos(for: conversationId)
        guard let firstId = canonical.first?.id else {
            return XCTFail("Missing first canonical todo")
        }

        store.setStatus(id: firstId, status: .done)
        let advanced = store.advanceNextCanonicalTodoIfNeeded(conversationId: conversationId)

        XCTAssertTrue(advanced)
        let refreshed = store.canonicalTodos(for: conversationId)
        XCTAssertEqual(refreshed.map(\.status), [.done, .inProgress, .pending])
    }

    func testLoadTodosDeduplicatesCanonicalEntriesPreservingDoneStatus() {
        let conversationId = UUID()
        do {
            let persisted = try XCTUnwrap(userDefaults)
            var seed = TodoStore(storageKey: storageKey, userDefaults: persisted)
            seed.todos = [
                TodoItem(
                    title: "Step A",
                    status: .pending,
                    priority: .medium,
                    source: .agent,
                    notes: "",
                    linkedFiles: [],
                    isPlanCanonical: true,
                    planOrder: 1,
                    planConversationId: conversationId
                ),
                TodoItem(
                    title: "Step A",
                    status: .done,
                    priority: .high,
                    source: .agent,
                    notes: "completed",
                    linkedFiles: ["Sources/App.swift"],
                    isPlanCanonical: true,
                    planOrder: 0,
                    planConversationId: conversationId
                ),
                TodoItem(
                    title: "Step B",
                    status: .pending,
                    priority: .medium,
                    source: .agent,
                    notes: "",
                    linkedFiles: [],
                    isPlanCanonical: true,
                    planOrder: 2,
                    planConversationId: conversationId
                ),
            ]
            seed.saveTodos()
            seed = TodoStore(storageKey: storageKey, userDefaults: persisted)

            let canonical = seed.canonicalTodos(for: conversationId)
            XCTAssertEqual(canonical.count, 2)
            XCTAssertEqual(canonical.first(where: { $0.title == "Step A" })?.status, .done)
            XCTAssertEqual(canonical.first(where: { $0.title == "Step A" })?.planOrder, 0)
            XCTAssertEqual(canonical.first(where: { $0.title == "Step A" })?.priority, .high)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUpsertCanonicalPlanTodosCollapsesScopedDuplicates() {
        let store = makeStore()
        let conversationId = UUID()
        store.todos = [
            TodoItem(
                title: "Definire baseline tecnica",
                status: .pending,
                priority: .medium,
                source: .agent,
                notes: "",
                linkedFiles: [],
                isPlanCanonical: true,
                planOrder: 1,
                planConversationId: conversationId
            ),
            TodoItem(
                title: "Definire baseline tecnica",
                status: .done,
                priority: .high,
                source: .agent,
                notes: "already completed",
                linkedFiles: [],
                isPlanCanonical: true,
                planOrder: 0,
                planConversationId: conversationId
            ),
        ]

        store.upsertCanonicalPlanTodos(
            ["Definire baseline tecnica", "Implementare modulo LanguageService"],
            conversationId: conversationId
        )

        let canonical = store.canonicalTodos(for: conversationId)
        XCTAssertEqual(canonical.count, 2)
        XCTAssertEqual(canonical.first(where: { $0.title == "Definire baseline tecnica" })?.status, .done)
        XCTAssertEqual(canonical.first(where: { $0.title == "Definire baseline tecnica" })?.planOrder, 0)
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

    func testRemovedCanonicalTasksAreDeletedAndEmitBlockedCallback() {
        let store = makeStore()
        var callbackEvents: [(title: String, status: TodoStatus, conversationId: UUID?)] = []
        store.onCanonicalTodoStatusChange = { title, status, conversationId in
            callbackEvents.append((title, status, conversationId))
        }

        store.upsertCanonicalPlanTodos(["Task 1", "Task 2"])
        store.upsertCanonicalPlanTodos(["Task 1"])

        let removed = store.todos.first { $0.title == "Task 2" }
        XCTAssertNil(removed)
        XCTAssertEqual(callbackEvents.count, 1)
        XCTAssertEqual(callbackEvents.first?.title, "Task 2")
        XCTAssertEqual(callbackEvents.first?.status, .blocked)
    }

    func testEmptyPlanTodosDoesNotMutateCanonicalTasks() {
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
        XCTAssertEqual(removedTask?.status, .pending)
        XCTAssertEqual(removedTask?.notes, "")
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
            linkedFiles: ["App/SoloCodeApp/Sources/PlanOptionsParser.swift"]
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

    func testCanonicalTodosAreScopedPerConversation() {
        let store = makeStore()
        let conversationA = UUID()
        let conversationB = UUID()

        store.upsertCanonicalPlanTodos(["Task A1", "Task A2"], conversationId: conversationA)
        store.upsertCanonicalPlanTodos(["Task B1"], conversationId: conversationB)

        let scopedA = store.canonicalTodos(for: conversationA).map(\.title)
        let scopedB = store.canonicalTodos(for: conversationB).map(\.title)

        XCTAssertEqual(Set(scopedA), Set(["Task A1", "Task A2"]))
        XCTAssertEqual(Set(scopedB), Set(["Task B1"]))
    }

    func testUpsertCanonicalOnlyFromAgentRespectsConversationScope() {
        let store = makeStore()
        let conversationA = UUID()
        let conversationB = UUID()

        store.upsertCanonicalPlanTodos(["Scope task"], conversationId: conversationA)
        store.upsertCanonicalPlanTodos(["Scope task"], conversationId: conversationB)

        let updatedInA = store.upsertCanonicalOnlyFromAgent(
            id: nil,
            title: "Scope task",
            status: .inProgress,
            priority: .high,
            notes: "A running",
            linkedFiles: [],
            conversationId: conversationA
        )

        XCTAssertTrue(updatedInA)
        let statusA = store.canonicalTodos(for: conversationA).first?.status
        let statusB = store.canonicalTodos(for: conversationB).first?.status
        XCTAssertEqual(statusA, .inProgress)
        XCTAssertEqual(statusB, .pending)
    }

    func testUpsertFromAgentStoresConversationIdForRuntimeTodo() {
        let store = makeStore()
        let conversationId = UUID()

        store.upsertFromAgent(
            id: nil,
            title: "Code Review & Test",
            status: .pending,
            priority: .high,
            notes: "Review and run tests",
            linkedFiles: [],
            conversationId: conversationId
        )

        let runtimeTodo = store.todos.first { $0.title == "Code Review & Test" }
        XCTAssertEqual(runtimeTodo?.isPlanCanonical, false)
        XCTAssertEqual(runtimeTodo?.planConversationId, conversationId)
    }

    func testUpsertFromAgentRespectsConversationScopeForRuntimeTitleMatch() {
        let store = makeStore()
        let conversationA = UUID()
        let conversationB = UUID()

        store.upsertFromAgent(
            id: nil,
            title: "Code Review & Test",
            status: .pending,
            priority: .high,
            notes: "A review",
            linkedFiles: [],
            conversationId: conversationA
        )
        store.upsertFromAgent(
            id: nil,
            title: "Code Review & Test",
            status: .blocked,
            priority: .high,
            notes: "B blocked",
            linkedFiles: [],
            conversationId: conversationB
        )

        store.upsertFromAgent(
            id: nil,
            title: "Code Review & Test",
            status: .done,
            priority: .high,
            notes: "A completed",
            linkedFiles: [],
            conversationId: conversationA
        )

        let todoA = store.todos.first { $0.planConversationId == conversationA }
        let todoB = store.todos.first { $0.planConversationId == conversationB }
        XCTAssertEqual(todoA?.status, .done)
        XCTAssertEqual(todoB?.status, .blocked)
    }

    func testDisplayTodosForChatScopesCanonicalAndRuntimeByConversation() {
        let store = makeStore()
        let conversationA = UUID()
        let conversationB = UUID()

        store.upsertCanonicalPlanTodos(["A canonical"], conversationId: conversationA)
        store.upsertCanonicalPlanTodos(["B canonical"], conversationId: conversationB)
        store.upsertFromAgent(
            id: nil,
            title: "A runtime",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationA
        )
        store.upsertFromAgent(
            id: nil,
            title: "B runtime",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationB
        )

        let visibleA = Set(store.displayTodosForChat(for: conversationA).map(\.title))
        let visibleB = Set(store.displayTodosForChat(for: conversationB).map(\.title))

        XCTAssertEqual(visibleA, Set(["A canonical", "A runtime"]))
        XCTAssertEqual(visibleB, Set(["B canonical", "B runtime"]))
    }

    func testDisplayTodosForChatFallsBackToLegacyUnscopedTodos() {
        let store = makeStore()
        store.upsertCanonicalPlanTodos(["Legacy canonical"])
        store.upsertFromAgent(
            id: nil,
            title: "Legacy runtime",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: nil
        )

        let visible = Set(store.displayTodosForChat(for: UUID()).map(\.title))
        XCTAssertEqual(visible, Set(["Legacy canonical", "Legacy runtime"]))
    }

    func testDisplayTodosForChatMergesScopedAndLegacyUnscopedRuntimeTodos() {
        let store = makeStore()
        let conversationId = UUID()
        store.upsertFromAgent(
            id: nil,
            title: "Legacy runtime",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: nil
        )
        store.upsertFromAgent(
            id: nil,
            title: "Scoped runtime",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )

        let visible = Set(store.displayTodosForChat(for: conversationId).map(\.title))
        XCTAssertEqual(visible, Set(["Scoped runtime", "Legacy runtime"]))
    }

    func testAdvanceNextRuntimeTodoUsesUnscopedPoolWhenConversationIdIsNil() {
        let store = makeStore()
        let firstId = UUID()
        let secondId = UUID()
        store.upsertFromAgent(
            id: firstId,
            title: "First",
            status: .inProgress,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: nil
        )
        store.upsertFromAgent(
            id: secondId,
            title: "Second",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: nil
        )
        store.setStatus(id: firstId, status: .done)
        XCTAssertTrue(store.advanceNextRuntimeTodoIfNeeded(conversationId: nil))
        let second = store.todos.first { $0.id == secondId }
        XCTAssertNotNil(second)
        XCTAssertEqual(second?.status, .inProgress)
    }

    func testAdvanceNextRuntimeTodoProceedsWhenCanonicalStepsAreAllDone() {
        let store = makeStore()
        let conversationId = UUID()
        store.upsertCanonicalPlanTodos(["Only step"], conversationId: conversationId)
        for item in store.todos.filter({
            $0.isPlanCanonical && $0.planConversationId == conversationId
        }) {
            store.setStatus(id: item.id, status: .done)
        }

        let firstRuntime = UUID()
        let secondRuntime = UUID()
        store.upsertFromAgent(
            id: firstRuntime,
            title: "Runtime A",
            status: .inProgress,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )
        store.upsertFromAgent(
            id: secondRuntime,
            title: "Runtime B",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )
        store.setStatus(id: firstRuntime, status: .done)
        XCTAssertTrue(store.advanceNextRuntimeTodoIfNeeded(conversationId: conversationId))
        let second = store.todos.first { $0.id == secondRuntime }
        XCTAssertEqual(second?.status, .inProgress)
    }

    func testAdvanceNextRuntimeTodoStillBlockedWhenCanonicalHasPendingStep() {
        let store = makeStore()
        let conversationId = UUID()
        store.upsertCanonicalPlanTodos(["Open plan"], conversationId: conversationId)
        let runtimeId = UUID()
        store.upsertFromAgent(
            id: runtimeId,
            title: "Runtime",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )
        XCTAssertFalse(store.advanceNextRuntimeTodoIfNeeded(conversationId: conversationId))
        XCTAssertEqual(store.todos.first { $0.id == runtimeId }?.status, .pending)
    }

    func testPlanConversationIdAfterUpsertFindsRowMergedByTitle() {
        let store = makeStore()
        let conversationId = UUID()
        let existingId = UUID()
        store.upsertFromAgent(
            id: existingId,
            title: "Merged title",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )
        let patchId = UUID()
        store.upsertFromAgent(
            id: patchId,
            title: "Merged title",
            status: .done,
            priority: .high,
            notes: nil,
            linkedFiles: [],
            conversationId: nil
        )
        let resolved = store.planConversationIdForRuntimeTodoAfterUpsert(
            preferredId: patchId,
            normalizedTitle: "Merged title",
            eventConversationId: conversationId
        )
        XCTAssertEqual(resolved, conversationId)
    }

    func testResolveComposerTodoItemsMatchesDisplayTodosForChatCanonicalPlusRuntime() {
        let store = makeStore()
        let conversationId = UUID()
        store.upsertCanonicalPlanTodos(["Step A", "Step B"], conversationId: conversationId)
        store.upsertFromAgent(
            id: nil,
            title: "command_execution",
            status: .inProgress,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )

        let resolved = resolveComposerTodoItems(
            todoStore: store,
            conversationId: conversationId
        )
        let displayed = store.displayTodosForChat(for: conversationId)
        XCTAssertEqual(resolved.map(\.id), displayed.map(\.id))
        XCTAssertEqual(
            Set(resolved.map(\.title)),
            Set(["Step A", "Step B", "command_execution"])
        )
    }

    func testResolveComposerTodoItemsFallsBackToChatTodosWhenCanonicalMissing() {
        let store = makeStore()
        let conversationId = UUID()
        store.upsertFromAgent(
            id: nil,
            title: "Scoped runtime",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )

        let visible = Set(
            resolveComposerTodoItems(
                todoStore: store,
                conversationId: conversationId
            ).map(\.title)
        )

        XCTAssertEqual(visible, Set(["Scoped runtime"]))
    }

    func testResolveComposerTodoItemsMatchesDisplayTodosLegacyUnscopedFallback() {
        let store = makeStore()
        let conversationId = UUID()
        store.upsertFromAgent(
            id: nil,
            title: "Legacy runtime",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: nil
        )

        let resolved = resolveComposerTodoItems(
            todoStore: store,
            conversationId: conversationId
        )
        let displayed = store.displayTodosForChat(for: conversationId)
        XCTAssertEqual(resolved.map(\.id), displayed.map(\.id))
        XCTAssertEqual(resolved.map(\.title), ["Legacy runtime"])
    }

    func testOperationalPlaceholdersAreExcludedFromVisibleTodoQueries() {
        let store = makeStore()
        let conversationId = UUID()

        store.upsertFromAgent(
            id: nil,
            title: "Runtime placeholder",
            status: .inProgress,
            priority: .medium,
            notes: "internal runtime state",
            activeForm: "Running",
            isOperationalPlaceholder: true,
            linkedFiles: [],
            conversationId: conversationId
        )
        store.upsertFromAgent(
            id: nil,
            title: "Real task",
            status: .pending,
            priority: .high,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )

        XCTAssertEqual(store.userVisibleTodos.map(\.title), ["Real task"])
        XCTAssertEqual(store.displayTodosForChat(for: conversationId).map(\.title), ["Real task"])
        XCTAssertEqual(store.openTodosCount, 1)
    }

    func testClearDoesNotFireCanonicalCallback() {
        let store = makeStore()
        store.upsertCanonicalPlanTodos(["Step A", "Step B"])

        var callbackFired = false
        store.onCanonicalTodoStatusChange = { _, _, _ in
            callbackFired = true
        }

        store.clear()

        XCTAssertTrue(store.todos.isEmpty)
        XCTAssertFalse(callbackFired, "clear() should not fire onCanonicalTodoStatusChange")
    }

    func testClearAgentTodosDoesNotFireCanonicalCallback() {
        let store = makeStore()
        store.upsertCanonicalPlanTodos(["Plan step"])
        store.add(title: "Agent task", source: .agent)

        var callbackFired = false
        store.onCanonicalTodoStatusChange = { _, _, _ in
            callbackFired = true
        }

        store.clearAgentTodos(includePlanCanonical: true)

        XCTAssertEqual(store.todos.count, 0)
        XCTAssertFalse(callbackFired, "clearAgentTodos should not fire onCanonicalTodoStatusChange")
    }
}
