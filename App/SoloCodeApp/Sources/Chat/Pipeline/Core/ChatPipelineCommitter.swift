import Foundation

@MainActor
enum ChatPipelineCommitter {
    static func commit(
        _ state: ChatTurnState,
        chatStore: ChatStore,
        persistImmediately: Bool
    ) {
        chatStore.updateAssistantMessagePipelineState(
            messageId: state.assistantMessageId,
            state: state,
            in: state.conversationId,
            persistImmediately: persistImmediately
        )
    }
}
