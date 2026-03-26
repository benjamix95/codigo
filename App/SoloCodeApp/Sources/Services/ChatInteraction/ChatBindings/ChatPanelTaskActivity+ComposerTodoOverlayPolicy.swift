import Foundation

/// Policy pura todo-overlay composer (condivisa da `ChatPanelView` retention).
enum ChatPanelComposerTodoPolicy {
    static let retentionGraceIntervalSeconds: CFAbsoluteTime = 0.75
}

func shouldHoldComposerTodoOverlay(
    incomingItems: [TodoItem],
    retainedItems: [TodoItem],
    isLoading: Bool,
    isStreaming: Bool,
    hasRecentNonEmptySnapshot: Bool
) -> Bool {
    !hasVisibleComposerTodoOverlay(items: incomingItems)
        && hasVisibleComposerTodoOverlay(items: retainedItems)
        && (isLoading || isStreaming || hasRecentNonEmptySnapshot)
}

func resolveEffectiveComposerTodoItems(
    incomingItems: [TodoItem],
    retainedItems: [TodoItem],
    isLoading: Bool,
    isStreaming: Bool,
    hasRecentNonEmptySnapshot: Bool
) -> [TodoItem] {
    if hasVisibleComposerTodoOverlay(items: incomingItems) {
        return incomingItems
    }
    if shouldHoldComposerTodoOverlay(
        incomingItems: incomingItems,
        retainedItems: retainedItems,
        isLoading: isLoading,
        isStreaming: isStreaming,
        hasRecentNonEmptySnapshot: hasRecentNonEmptySnapshot
    ) {
        return retainedItems
    }
    return []
}

@MainActor
func resolveComposerTodoItems(
    todoStore: TodoStore,
    conversationId: UUID?
) -> [TodoItem] {
    guard let conversationId else {
        return []
    }
    return todoStore.displayTodosForChat(for: conversationId)
}
