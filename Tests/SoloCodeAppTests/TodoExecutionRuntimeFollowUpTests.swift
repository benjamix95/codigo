import XCTest
@testable import CoderIDE

@MainActor
final class TodoExecutionRuntimeFollowUpTests: XCTestCase {
    func testNormalizeExecutionTitlesDoesNotAppendFollowUpsForAnalysisOnlySteps() {
        let titles = TodoExecutionFollowUpPolicy.normalizeExecutionTitles([
            "Analizzare stack trace",
            "Leggere log runtime",
        ])

        XCTAssertEqual(
            titles,
            [
                "Analizzare stack trace",
                "Leggere log runtime",
                "Doc Writer",
            ]
        )
    }

    func testMissingFinalFollowUpTitlesRequiresRealMutationTodo() {
        let store = makeStore()
        let conversationId = UUID()

        store.upsertFromAgent(
            id: nil,
            title: "Analizzare stack trace",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )

        XCTAssertEqual(
            TodoExecutionFollowUpPolicy.missingFinalFollowUpTitles(
                in: store.todos,
                conversationId: conversationId
            ),
            []
        )

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
            TodoExecutionFollowUpPolicy.missingFinalFollowUpTitles(
                in: store.todos,
                conversationId: conversationId
            ),
            [
                "Code Review & Test",
                "Doc Writer",
            ]
        )
    }

    func testMissingFinalFollowUpTitlesForAnalyticalChecklistAddsDocWriterOnly() {
        let store = makeStore()
        let conversationId = UUID()

        store.upsertFromAgent(
            id: nil,
            title: "Definire scope",
            status: .done,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )
        store.upsertFromAgent(
            id: nil,
            title: "Scansionare servizi runtime",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )

        XCTAssertEqual(
            TodoExecutionFollowUpPolicy.missingFinalFollowUpTitles(
                in: store.todos,
                conversationId: conversationId
            ),
            ["Doc Writer"]
        )
    }

    func testImplicitRuntimeFollowUpTitlesAddsReviewAndDocWriterForImplementationFlow() {
        let store = makeStore()
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
            TodoExecutionFollowUpPolicy.implicitRuntimeFollowUpTitles(
                in: store.todos,
                conversationId: conversationId
            ),
            [
                "Code Review & Test",
                "Doc Writer",
            ]
        )
    }

    func testAdvanceNextRuntimeTodoPromotesReviewBeforeDocWriter() {
        let store = makeStore()
        let conversationId = UUID()

        let implementationId = UUID()
        store.upsertFromAgent(
            id: implementationId,
            title: "Implementare fix stream",
            status: .done,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )
        store.upsertFromAgent(
            id: nil,
            title: "Code Review & Test",
            status: .pending,
            priority: .high,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )
        store.upsertFromAgent(
            id: nil,
            title: "Doc Writer",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )

        XCTAssertTrue(store.advanceNextRuntimeTodoIfNeeded(conversationId: conversationId))
        XCTAssertEqual(
            store.displayTodosForChat(for: conversationId).map(\.title),
            [
                "Implementare fix stream",
                "Code Review & Test",
                "Doc Writer",
            ]
        )
        XCTAssertEqual(
            store.todos.first { $0.title == "Code Review & Test" }?.status,
            .inProgress
        )

        let reviewId = try! XCTUnwrap(store.todos.first { $0.title == "Code Review & Test" }?.id)
        store.setStatus(id: reviewId, status: .done)

        XCTAssertTrue(store.advanceNextRuntimeTodoIfNeeded(conversationId: conversationId))
        XCTAssertEqual(
            store.todos.first { $0.title == "Doc Writer" }?.status,
            .inProgress
        )
    }

    func testDisplayTodosForChatKeepsCompletedFollowUpsVisible() {
        let store = makeStore()
        let conversationId = UUID()

        store.upsertFromAgent(
            id: nil,
            title: "Implementare fix stream",
            status: .done,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )
        store.upsertFromAgent(
            id: nil,
            title: "Code Review & Test",
            status: .done,
            priority: .high,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )
        store.upsertFromAgent(
            id: nil,
            title: "Doc Writer",
            status: .done,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )

        XCTAssertEqual(
            store.displayTodosForChat(for: conversationId).map(\.title),
            [
                "Implementare fix stream",
                "Code Review & Test",
                "Doc Writer",
            ]
        )
    }

    func testDisplayTodosForChatKeepsSequentialOrderAfterCompletion() {
        let store = makeStore()
        let conversationId = UUID()

        store.upsertFromAgent(
            id: nil,
            title: "Definire scope",
            status: .done,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )
        store.upsertFromAgent(
            id: nil,
            title: "Scansionare servizi runtime",
            status: .done,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )
        store.upsertFromAgent(
            id: nil,
            title: "Consolidare findings / output",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )
        store.upsertFromAgent(
            id: nil,
            title: "Doc Writer",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )

        XCTAssertEqual(
            store.displayTodosForChat(for: conversationId).map(\.title),
            [
                "Definire scope",
                "Scansionare servizi runtime",
                "Consolidare findings / output",
                "Doc Writer",
            ]
        )
    }

    func testAdvanceNextRuntimeTodoStopsWhenEarlierTodoIsBlocked() {
        let store = makeStore()
        let conversationId = UUID()

        store.upsertFromAgent(
            id: nil,
            title: "Definire scope",
            status: .done,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )
        store.upsertFromAgent(
            id: nil,
            title: "Scansionare servizi runtime",
            status: .blocked,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )
        store.upsertFromAgent(
            id: nil,
            title: "Consolidare findings / output",
            status: .pending,
            priority: .medium,
            notes: nil,
            linkedFiles: [],
            conversationId: conversationId
        )

        XCTAssertFalse(store.advanceNextRuntimeTodoIfNeeded(conversationId: conversationId))
        XCTAssertEqual(
            store.todos.first { $0.title == "Consolidare findings / output" }?.status,
            .pending
        )
    }

    private func makeStore() -> TodoStore {
        let suiteName = "TodoExecutionRuntimeFollowUpTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return TodoStore(
            storageKey: "CoderIDE.todos.tests.\(UUID().uuidString)",
            userDefaults: defaults
        )
    }
}
