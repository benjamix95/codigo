import CoderEngine
import Foundation

func mainChatUIIntentRuntimeTurnState(
    response: MainChatUIIntentResponseBridge?,
    targetConversationId: UUID?
) -> ChatTurnState? {
    guard let targetConversationId,
          let runtimeSnapshot = response?.state?.runtimeSnapshot
    else { return nil }
    let turnState = runtimeSnapshot.turnState.chatTurnState
    guard turnState.conversationId == targetConversationId else { return nil }
    return turnState
}

extension ChatPanelView {
    @MainActor
    internal func syncConversationRuntimeFromMainChatUIIntent(
        response: MainChatUIIntentResponseBridge?,
        conversationId targetConversationId: UUID?
    ) {
        guard let turnState = mainChatUIIntentRuntimeTurnState(
            response: response,
            targetConversationId: targetConversationId
        ) else { return }
        conversationRuntime.activeTurnStateByConversation[turnState.conversationId] = turnState
        conversationRuntime.renderSnapshotByConversation[turnState.conversationId] = turnState
        conversationRuntime.cachePipelineTurnStateForAssistantMessage(turnState)
    }
}
