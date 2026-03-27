import Foundation
import SwiftUI

/// Policy pura todo-overlay composer (condivisa da `ChatPanelView` retention).
enum ChatPanelComposerTodoPolicy {
    static let retentionGraceIntervalSeconds: CFAbsoluteTime = 0.75
}

func shouldShowComposerTodoOverlay(
    items: [TodoItem],
    coderMode: CoderMode,
    planToggleEnabled: Bool,
    planFlowPhase: PlanFlowPhase,
    planningState: PlanningState
) -> Bool {
    guard hasVisibleComposerTodoOverlay(items: items) else { return false }

    let planSurfaceActive =
        coderMode == .plan
        || planToggleEnabled
        || planFlowPhase == .analyzing
        || planFlowPhase == .questioning
        || planFlowPhase == .generating
        || planFlowPhase == .proposalReady
        || planFlowPhase == .readyToBuild
        || planFlowPhase == .building

    if planSurfaceActive {
        return false
    }

    if case .awaitingClarification = planningState {
        return false
    }
    if case .awaitingChoice = planningState {
        return false
    }

    return true
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
    conversationId: UUID?,
    includeOperationalRuntimeTodos: Bool = false
) -> [TodoItem] {
    guard let conversationId else {
        return []
    }
    return todoStore.displayTodosForComposer(
        for: conversationId,
        includeOperationalRuntimeTodos: includeOperationalRuntimeTodos
    )
}
