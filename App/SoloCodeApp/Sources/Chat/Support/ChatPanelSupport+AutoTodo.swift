import Foundation

let autoTodoGenericFallbackTitle = "Complete the required operational steps"

func autoTodoRuntimeNotes(operationCount: Int) -> String {
    switch operationCount {
    case ..<1:
        return "Auto-generated: execution started before an explicit todo was created."
    case 1:
        return "Auto-generated: tracking live operational activity until the agent publishes an explicit todo."
    default:
        return "Auto-generated: tracking \(operationCount) operational steps until the agent publishes an explicit todo."
    }
}

func preferredAutoTodoTitle(currentTitle: String?, candidateTitle: String) -> String {
    let current = currentTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let candidate = candidateTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !candidate.isEmpty else { return current }
    guard !current.isEmpty else { return candidate }
    if current == autoTodoGenericFallbackTitle, candidate != autoTodoGenericFallbackTitle {
        return candidate
    }
    return current
}

func preferredAutoTodoActiveForm(currentActiveForm: String, immediateLabel: String, title: String) -> String {
    let current = currentActiveForm.trimmingCharacters(in: .whitespacesAndNewlines)
    let immediate = immediateLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !immediate.isEmpty { return immediate }
    if !current.isEmpty { return current }
    return fallback
}

func mergedAutoTodoLinkedFiles(existing: [String], incoming: [String]) -> [String] {
    Array(Set(existing + incoming)).sorted()
}

func shouldShowLiveTodoCardInChat(
    hasSwarmSteps: Bool,
    hasLiveSwarmCards: Bool,
    hasPipelineProgress: Bool
) -> Bool {
    _ = hasPipelineProgress
    return !(hasSwarmSteps || hasLiveSwarmCards)
}

func resolveTodoCardAssistantMessageId(
    messages: [ChatMessage],
    activeAssistantMessageId: UUID?,
    latestAssistantMessageIdWithTrace: UUID?,
    pipelineAssistantMessageId: UUID?,
    latestVisibleAssistantMessageId: UUID?
) -> UUID? {
    let assistantMessageIds = Set(
        messages.lazy
            .filter { $0.role == .assistant }
            .map(\.id)
    )

    func firstValid(_ candidate: UUID?) -> UUID? {
        guard let candidate else { return nil }
        guard assistantMessageIds.contains(candidate) else { return nil }
        return candidate
    }

    return firstValid(activeAssistantMessageId)
        ?? firstValid(latestAssistantMessageIdWithTrace)
        ?? firstValid(pipelineAssistantMessageId)
        ?? firstValid(latestVisibleAssistantMessageId)
}
