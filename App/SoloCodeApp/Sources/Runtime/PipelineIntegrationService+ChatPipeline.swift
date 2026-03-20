import CoderEngine
import Foundation

extension PipelineIntegrationService {
    func consumePipelineUIEvent(_ event: PipelineUIEvent, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        let providerId = runtime.chatTurnState.providerId ?? runtime.providerId
        let adapted = PipelineUIEventAdapter.events(
            from: event,
            conversationId: conversationId,
            assistantMessageId: runtime.assistantMessageId,
            turnId: runtime.chatTurnState.turnId,
            providerId: providerId
        )
        consumePipelineEvents(adapted, for: conversationId)
    }

    func consumeRawPipelineArtifacts(
        rawType: String,
        payload: [String: String],
        for conversationId: UUID
    ) {
        guard let runtime = runtime(for: conversationId) else { return }
        let providerId = runtime.chatTurnState.providerId ?? runtime.providerId
        let adapted = RawArtifactEventAdapter.events(
            rawType: rawType,
            payload: payload,
            conversationId: conversationId,
            assistantMessageId: runtime.assistantMessageId,
            turnId: runtime.chatTurnState.turnId,
            providerId: providerId
        )
        consumePipelineEvents(adapted, for: conversationId)
    }

    func consumePipelineEvents(_ events: [ChatPipelineEvent], for conversationId: UUID) {
        guard !events.isEmpty,
              let runtime = runtime(for: conversationId),
              let chatStore
        else { return }
        var shouldPersistImmediately = false
        for event in events {
            let sequenced = ChatPipelineEvent(
                conversationId: event.conversationId,
                assistantMessageId: event.assistantMessageId,
                turnId: event.turnId,
                sequence: runtime.nextPipelineSequence,
                source: event.source,
                kind: event.kind,
                payload: event.payload,
                timestamp: event.timestamp
            )
            runtime.nextPipelineSequence += 1
            runtime.chatTurnState = MainChatRustBridge.reduce(
                state: runtime.chatTurnState,
                event: sequenced
            ) ?? ChatPipelineReducer.apply(
                state: runtime.chatTurnState,
                event: sequenced
            )
            if sequenced.kind == .turnCompleted || sequenced.kind == .turnFailed {
                shouldPersistImmediately = true
            }
        }
        ChatPipelineCommitter.commit(
            runtime.chatTurnState,
            chatStore: chatStore,
            persistImmediately: shouldPersistImmediately
        )
    }
}
