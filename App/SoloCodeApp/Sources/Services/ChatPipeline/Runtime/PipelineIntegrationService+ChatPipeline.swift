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
            if !applyPipelineEventThroughRustBoundary(
                sequenced,
                runtime: runtime,
                chatStore: chatStore
            ) {
                if shouldSkipRustStoreBootstrapForTests(
                    environment: ProcessInfo.processInfo.environment
                ) {
                    runtime.chatTurnState = ChatPipelineReducer.apply(
                        state: runtime.chatTurnState,
                        event: sequenced
                    )
                    ChatPipelineCommitter.commit(
                        runtime.chatTurnState,
                        chatStore: chatStore,
                        persistImmediately: false
                    )
                } else {
                    NSLog(
                        "[PipelineIntegrationService] Rust pipeline boundary unavailable for %@",
                        sequenced.kind.rawValue
                    )
                    continue
                }
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
        if shouldPersistImmediately {
            chatStore.saveConversationsImmediately()
        } else {
            chatStore.saveConversations()
        }
    }

    private func applyPipelineEventThroughRustBoundary(
        _ event: ChatPipelineEvent,
        runtime: PipelineConversationRuntime,
        chatStore: ChatStore
    ) -> Bool {
        let runtimeSnapshot = MainChatRuntimeSnapshotBridge(
            turnState: MainChatBridgeState(runtime.chatTurnState),
            mode: .agent,
            directStream: nil,
            plan: nil,
            output: nil
        )
        guard let response = RustMainChatStoreAdapter.applyPipelineEvent(
            event,
            to: chatStore,
            runtimeSnapshot: runtimeSnapshot,
            selectedConversationId: runtime.conversationId,
            draftText: "",
            planPanelVisible: false,
            followLive: true,
            collapsedArtifactsByTurn: [:],
            preserveLocalMessages: false
        ), let nextState = response.state?.runtimeSnapshot?.turnState.chatTurnState else {
            return false
        }
        runtime.chatTurnState = nextState
        return true
    }
}
