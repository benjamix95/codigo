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
            if sequenced.kind == .textDelta || sequenced.kind == .textReplace {
                let delta = sequenced.payload["delta"] ?? sequenced.payload["replacement"] ?? ""
                print(
                    "[ChatDebug] pipeline \(sequenced.kind.rawValue): delta=\(delta.count) payload=\(sequenced.payload.keys.sorted().joined(separator: ","))"
                )
            }
            let previousTextByStreamId = runtime.chatTurnState.textByStreamId
            runtime.chatTurnState = MainChatRustBridge.reduce(
                state: runtime.chatTurnState,
                event: sequenced
            ) ?? ChatPipelineReducer.apply(
                state: runtime.chatTurnState,
                event: sequenced
            )
            // Guard: if the Rust reducer handled a text event but did not
            // update textByStreamId, re-apply the Swift reducer's text
            // logic so that primary content always appears inline.
            if (sequenced.kind == .textDelta || sequenced.kind == .textReplace),
               runtime.chatTurnState.textByStreamId == previousTextByStreamId {
                let swiftReduced = ChatPipelineReducer.apply(
                    state: runtime.chatTurnState,
                    event: sequenced
                )
                runtime.chatTurnState.textByStreamId = swiftReduced.textByStreamId
                runtime.chatTurnState.orderedTextStreamIds = swiftReduced.orderedTextStreamIds
            }
            if sequenced.kind == .turnCompleted || sequenced.kind == .turnFailed {
                shouldPersistImmediately = true
            }
        }
        let primaryText = runtime.chatTurnState.primaryTextSnapshot
        let textKeys = runtime.chatTurnState.textByStreamId.keys.sorted()
        let streamIds = runtime.chatTurnState.orderedTextStreamIds
        if !primaryText.isEmpty || !events.filter({ $0.kind == .textDelta || $0.kind == .textReplace }).isEmpty {
            print(
                "[ChatDebug] commit: primaryText=\(primaryText.count) textKeys=\(textKeys.joined(separator: ",")) streamIds=\(streamIds.joined(separator: ",")) blocks=\(runtime.chatTurnState.blocks.count)"
            )
        }
        ChatPipelineCommitter.commit(
            runtime.chatTurnState,
            chatStore: chatStore,
            persistImmediately: shouldPersistImmediately
        )
    }
}
