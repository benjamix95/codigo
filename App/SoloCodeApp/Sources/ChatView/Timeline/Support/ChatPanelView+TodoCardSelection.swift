import Foundation

func shouldShowLiveTodoCardInChat(
    hasSwarmSteps: Bool,
    hasLiveSwarmCards: Bool,
    hasPipelineProgress: Bool
) -> Bool {
    _ = hasSwarmSteps
    _ = hasLiveSwarmCards
    _ = hasPipelineProgress
    return true
}

func resolveTodoCardAssistantMessageId(
    messages: [ChatMessage],
    activeAssistantMessageId: UUID?,
    latestAssistantMessageIdWithTrace: UUID?,
    pipelineAssistantMessageId: UUID?,
    latestVisibleAssistantMessageId: UUID?
) -> UUID? {
    let assistantMessagesById = Dictionary(
        uniqueKeysWithValues: messages.lazy
            .filter { $0.role == .assistant }
            .map { ($0.id, $0) }
    )

    func isVisibleAssistantMessage(_ message: ChatMessage) -> Bool {
        if message.planAttachment != nil {
            return true
        }
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty {
            return true
        }
        let snapshot = (message.primaryTextSnapshot ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !snapshot.isEmpty
    }

    func firstValid(_ candidate: UUID?, requireVisibleContent: Bool = false) -> UUID? {
        guard let candidate, let message = assistantMessagesById[candidate] else { return nil }
        if requireVisibleContent && !isVisibleAssistantMessage(message) {
            return nil
        }
        return candidate
    }

    return firstValid(activeAssistantMessageId, requireVisibleContent: true)
        ?? firstValid(latestAssistantMessageIdWithTrace)
        ?? firstValid(pipelineAssistantMessageId)
        ?? firstValid(latestVisibleAssistantMessageId)
}
