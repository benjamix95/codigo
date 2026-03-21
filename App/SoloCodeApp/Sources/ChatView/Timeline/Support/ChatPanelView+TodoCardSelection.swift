import Foundation

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
