import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

enum CoderMode: String, CaseIterable {
    case agent = "Agent"
    case codeReviewMultiSwarm = "Code Review"
    case debug = "Debug"
    case plan = "Plan"
    case ide = "IDE"
    case browser = "Browser"
    case mcpServer = "MCP Server"

    var color: Color {
        switch self {
        case .agent: return DesignSystem.Colors.agentColor
        case .codeReviewMultiSwarm: return DesignSystem.Colors.reviewColor
        case .debug: return DesignSystem.Colors.debugColor
        case .plan: return DesignSystem.Colors.planColor
        case .ide: return DesignSystem.Colors.ideColor
        case .browser: return DesignSystem.Colors.browserColor
        case .mcpServer: return DesignSystem.Colors.mcpColor
        }
    }

    var iconName: String {
        switch self {
        case .agent: return "brain.head.profile"
        case .codeReviewMultiSwarm: return "doc.text.magnifyingglass"
        case .debug: return "ladybug.fill"
        case .plan: return "list.bullet.rectangle"
        case .ide: return "sparkles"
        case .browser: return "globe"
        case .mcpServer: return "server.rack"
        }
    }

    var shortLabel: String {
        switch self {
        case .agent: return "Agent"
        case .codeReviewMultiSwarm: return "Review"
        case .debug: return "Debug"
        case .plan: return "Plan"
        case .ide: return "IDE"
        case .browser: return "Browser"
        case .mcpServer: return "MCP"
        }
    }
}

enum PlanningState: Equatable {
    case idle
    case awaitingClarification(questions: String)
    case awaitingChoice(planContent: String, options: [PlanOption])
}

enum PlanFlowPhase: Equatable {
    case idle
    case analyzing          // Phase 1: codebase analysis in progress
    case questioning        // Phase 2: generating/awaiting clarification questions
    case generating         // Phase 3: generating structured plan options
    case proposalReady
    case readyToBuild
    case building
}

enum ToolTraceTurnOutcome: Equatable {
    case success
    case failed
    case aborted
}

func toolTraceTurnOutcome(for flowState: ConversationFlowCoordinator.State) -> ToolTraceTurnOutcome {
    switch flowState {
    case .error:
        return .failed
    case .interrupted:
        return .aborted
    default:
        return .success
    }
}

func toolTraceTurnOutcome(
    pipelineSuccess: Bool,
    pipelineWasCancelled: Bool
) -> ToolTraceTurnOutcome {
    if pipelineSuccess { return .success }
    if pipelineWasCancelled { return .aborted }
    return .failed
}

func autoTodoFinalStatus(for outcome: ToolTraceTurnOutcome) -> TodoStatus {
    switch outcome {
    case .success:
        return .done
    case .failed, .aborted:
        return .blocked
    }
}

func rolloverAutoTodoOutcome(
    for flowState: ConversationFlowCoordinator.State,
    hasRunningOperations: Bool
) -> ToolTraceTurnOutcome {
    switch flowState {
    case .error:
        return .failed
    case .interrupted:
        return .aborted
    case .streaming:
        // A new turn started before the previous one reached completion.
        return .aborted
    case .idle, .completed:
        return hasRunningOperations ? .aborted : .success
    }
}

func todoIDsToAutoCompleteAfterSubagentBatch(
    todos: [TodoItem],
    conversationId: UUID? = nil,
    includePendingReviewTodo: Bool = false,
    excludeCanonicalTodos: Bool = false,
    reviewTodoTitle: String = "Code Review & Test"
) -> [UUID] {
    let normalizedReviewTitle = normalizedTodoTitle(reviewTodoTitle)
    let isInScope = todoConversationScopeFilter(todos: todos, conversationId: conversationId)
    let inProgressCandidates = todos.filter {
        isInScope($0)
            && $0.source == .agent
            && !$0.isOperationalPlaceholder
            && $0.status == .inProgress
            && (!excludeCanonicalTodos || !$0.isPlanCanonical)
    }
    let prioritizedInProgress = inProgressCandidates.sorted { lhs, rhs in
        let lhsHasActiveForm = !lhs.activeForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let rhsHasActiveForm = !rhs.activeForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if lhsHasActiveForm != rhsHasActiveForm { return lhsHasActiveForm && !rhsHasActiveForm }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.createdAt > rhs.createdAt
    }
    var ids = Set(prioritizedInProgress.prefix(1).map(\.id))
    if includePendingReviewTodo,
       let pendingReview = todos.first(where: {
           isInScope($0)
               && $0.source == .agent
               && !$0.isOperationalPlaceholder
               && $0.status == .pending
               && normalizedTodoTitle($0.title) == normalizedReviewTitle
       })
    {
        ids.insert(pendingReview.id)
    }
    return Array(ids)
}

func shouldAutoCompletePendingReviewTodo(subagentBatchPayload: [String: String]) -> Bool {
    let roles = Set(
        (subagentBatchPayload["roles"] ?? "")
            .split(separator: ",")
            .map { normalizeRoleToken(String($0)) }
            .filter { !$0.isEmpty }
    )
    return roles.contains("reviewer") && roles.contains("testwriter")
}

func todoConversationScopeFilter(
    todos: [TodoItem],
    conversationId: UUID?
) -> (TodoItem) -> Bool {
    guard let conversationId else { return { _ in true } }
    let visible = todos.filter { !$0.isOperationalPlaceholder }
    let planScopeIds = Set(visible.compactMap(\.planConversationId))
    return { todo in
        TodoChatDisplayPolicy.itemAppearsInChat(
            todo,
            conversationId: conversationId,
            visibleTodos: visible,
            planScopeIds: planScopeIds
        )
    }
}

func canScrollToTarget(
    _ target: AnyHashable,
    topAnchorId: String,
    bottomAnchorId: String,
    allowAnchorTargets: Bool,
    availableMessageIDs: Set<UUID>
) -> Bool {
    if let stringTarget = target as? String {
        guard allowAnchorTargets else { return false }
        return stringTarget == topAnchorId || stringTarget == bottomAnchorId
    }
    if let messageID = target as? UUID {
        return availableMessageIDs.contains(messageID)
    }
    return false
}

func shouldInvalidateChatTimelineForLiveMutation(eventType: String) -> Bool {
    switch eventType {
    case "todo_write", "todo_read", "plan_create", "plan_step_upsert", "plan_step_batch_update",
        "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
        "plan_request_user_input":
        return true
    default:
        return false
    }
}

// MARK: - Private Helpers

private func normalizeRoleToken(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "-", with: "")
        .lowercased()
}
