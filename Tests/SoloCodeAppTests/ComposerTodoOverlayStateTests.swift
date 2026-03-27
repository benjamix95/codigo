import XCTest
@testable import CoderIDE

final class ComposerTodoOverlayStateTests: XCTestCase {
    func testHasVisibleComposerTodoOverlayKeepsCompletedTodosVisibleButHidesPlaceholders() {
        XCTAssertTrue(
            hasVisibleComposerTodoOverlay(
                items: [
                    TodoItem(title: "Completato", status: .done),
                    TodoItem(title: "Placeholder", status: .inProgress, isOperationalPlaceholder: true),
                ]
            )
        )

        XCTAssertFalse(
            hasVisibleComposerTodoOverlay(
                items: [
                    TodoItem(title: "Placeholder", status: .inProgress, isOperationalPlaceholder: true),
                ]
            )
        )
    }

    func testComposerTodoAutoExpandSignatureIgnoresDoneAndOperationalPlaceholderTodos() {
        let activeId = UUID()

        let signature = composerTodoAutoExpandSignature(
            items: [
                TodoItem(id: activeId, title: "Analizza", status: .inProgress, planOrder: 1),
                TodoItem(title: "Fatto", status: .done, planOrder: 0),
                TodoItem(title: "Runtime", status: .pending, isOperationalPlaceholder: true, planOrder: 2),
            ]
        )

        XCTAssertEqual(signature, "\(activeId.uuidString)|in_progress|1")
    }

    func testComposerTodoAutoExpandSignatureChangesWhenActiveTodoSetChanges() {
        let initialSignature = composerTodoAutoExpandSignature(
            items: [
                TodoItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Uno", status: .pending, planOrder: 0),
            ]
        )

        let updatedSignature = composerTodoAutoExpandSignature(
            items: [
                TodoItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Uno", status: .done, planOrder: 0),
                TodoItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "Due", status: .inProgress, planOrder: 1),
            ]
        )

        XCTAssertNotEqual(initialSignature, updatedSignature)
        XCTAssertEqual(updatedSignature, "00000000-0000-0000-0000-000000000002|in_progress|1")
    }

    func testShouldHoldComposerTodoOverlayKeepsPreviousTodosDuringTransientGapWhileLoading() {
        let retained = [TodoItem(title: "In corso", status: .inProgress)]

        XCTAssertTrue(
            shouldHoldComposerTodoOverlay(
                incomingItems: [],
                retainedItems: retained,
                isLoading: true,
                isStreaming: false,
                hasRecentNonEmptySnapshot: false
            )
        )
    }

    func testShouldHoldComposerTodoOverlayKeepsPreviousTodosDuringStreamingWithoutRecentSnapshot() {
        let retained = [TodoItem(title: "In corso", status: .inProgress)]

        XCTAssertTrue(
            shouldHoldComposerTodoOverlay(
                incomingItems: [],
                retainedItems: retained,
                isLoading: false,
                isStreaming: true,
                hasRecentNonEmptySnapshot: false
            )
        )
    }

    func testShouldHoldComposerTodoOverlayKeepsPreviousTodosDuringRecentSnapshotGap() {
        let retained = [TodoItem(title: "In corso", status: .inProgress)]

        XCTAssertTrue(
            shouldHoldComposerTodoOverlay(
                incomingItems: [],
                retainedItems: retained,
                isLoading: false,
                isStreaming: false,
                hasRecentNonEmptySnapshot: true
            )
        )
    }

    func testResolveEffectiveComposerTodoItemsUsesRetainedTodosDuringTransientGap() {
        let retained = [TodoItem(title: "In corso", status: .inProgress)]

        let resolved = resolveEffectiveComposerTodoItems(
            incomingItems: [],
            retainedItems: retained,
            isLoading: true,
            isStreaming: false,
            hasRecentNonEmptySnapshot: false
        )

        XCTAssertEqual(resolved.map(\.title), ["In corso"])
    }

    func testResolveEffectiveComposerTodoItemsUsesRetainedTodosDuringStreamingGap() {
        let retained = [TodoItem(title: "In corso", status: .inProgress)]

        let resolved = resolveEffectiveComposerTodoItems(
            incomingItems: [],
            retainedItems: retained,
            isLoading: false,
            isStreaming: true,
            hasRecentNonEmptySnapshot: false
        )

        XCTAssertEqual(resolved.map(\.title), ["In corso"])
    }

    func testResolveEffectiveComposerTodoItemsClearsWhenGapIsNotTransient() {
        let retained = [TodoItem(title: "In corso", status: .inProgress)]

        let resolved = resolveEffectiveComposerTodoItems(
            incomingItems: [],
            retainedItems: retained,
            isLoading: false,
            isStreaming: false,
            hasRecentNonEmptySnapshot: false
        )

        XCTAssertTrue(resolved.isEmpty)
    }
}
