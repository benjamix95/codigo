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
        let coalescedEvents = coalescePipelineEvents(events)
        var shouldPersistImmediately = false
        let sequencedEvents = coalescedEvents.map { event -> ChatPipelineEvent in
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
            return sequenced
        }

        for sequenced in sequencedEvents where sequenced.kind == .textDelta || sequenced.kind == .textReplace {
            let delta = sequenced.payload["delta"] ?? sequenced.payload["replacement"] ?? ""
            print(
                "[ChatDebug] pipeline \(sequenced.kind.rawValue): delta=\(delta.count) payload=\(sequenced.payload.keys.sorted().joined(separator: ","))"
            )
        }

        if !applyPipelineEventsThroughRustBoundary(
            sequencedEvents,
            runtime: runtime,
            chatStore: chatStore
        ) {
            for sequenced in sequencedEvents {
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
        }

        if sequencedEvents.contains(where: { $0.kind == .turnCompleted || $0.kind == .turnFailed }) {
            shouldPersistImmediately = true
        }
        let primaryText = runtime.chatTurnState.primaryTextSnapshot
        let textKeys = runtime.chatTurnState.textByStreamId.keys.sorted()
        let streamIds = runtime.chatTurnState.orderedTextStreamIds
        if !primaryText.isEmpty || !coalescedEvents.filter({ $0.kind == .textDelta || $0.kind == .textReplace }).isEmpty {
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

    private func applyPipelineEventsThroughRustBoundary(
        _ events: [ChatPipelineEvent],
        runtime: PipelineConversationRuntime,
        chatStore: ChatStore
    ) -> Bool {
        guard !events.isEmpty else { return true }
        let runtimeSnapshot = MainChatRuntimeSnapshotBridge(
            turnState: MainChatBridgeState(runtime.chatTurnState),
            mode: .agent,
            directStream: nil,
            plan: nil,
            output: nil
        )
        guard let response = RustMainChatStoreAdapter.applyPipelineEvents(
            events,
            to: chatStore,
            runtimeSnapshot: runtimeSnapshot,
            selectedConversationId: runtime.conversationId,
            draftText: "",
            planPanelVisible: false,
            followLive: true,
            collapsedArtifactsByTurn: [:],
            preserveLocalMessages: false
        ), let nextState = response.state?.runtimeSnapshot?.turnState.chatTurnState else {
            if events.count == 1 {
                return applyPipelineEventThroughRustBoundary(
                    events[0],
                    runtime: runtime,
                    chatStore: chatStore
                )
            }
            return false
        }
        runtime.chatTurnState = nextState
        return true
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

    private func coalescePipelineEvents(_ events: [ChatPipelineEvent]) -> [ChatPipelineEvent] {
        guard events.count > 1 else { return events }

        var coalesced: [ChatPipelineEvent] = []
        for event in events {
            guard let last = coalesced.last,
                  canCoalescePipelineEvent(event, with: last) else {
                coalesced.append(event)
                continue
            }

            switch event.kind {
            case .textDelta:
                var mergedPayload = last.payload
                mergedPayload["delta"] = (last.payload["delta"] ?? "") + (event.payload["delta"] ?? "")
                coalesced[coalesced.count - 1] = ChatPipelineEvent(
                    conversationId: last.conversationId,
                    assistantMessageId: last.assistantMessageId,
                    turnId: last.turnId,
                    sequence: last.sequence,
                    source: last.source,
                    kind: last.kind,
                    payload: mergedPayload,
                    timestamp: event.timestamp
                )
            case .textReplace:
                var mergedPayload = last.payload
                mergedPayload["replacement"] = event.payload["replacement"] ?? last.payload["replacement"]
                coalesced[coalesced.count - 1] = ChatPipelineEvent(
                    conversationId: last.conversationId,
                    assistantMessageId: last.assistantMessageId,
                    turnId: last.turnId,
                    sequence: last.sequence,
                    source: last.source,
                    kind: last.kind,
                    payload: mergedPayload,
                    timestamp: event.timestamp
                )
            default:
                coalesced.append(event)
            }
        }
        return coalesced
    }

    private func canCoalescePipelineEvent(
        _ event: ChatPipelineEvent,
        with previous: ChatPipelineEvent
    ) -> Bool {
        guard event.conversationId == previous.conversationId,
              event.assistantMessageId == previous.assistantMessageId,
              event.turnId == previous.turnId,
              event.source == previous.source,
              event.kind == previous.kind else { return false }

        switch event.kind {
        case .textDelta, .textReplace:
            return event.payload["stream_id"] == previous.payload["stream_id"]
                && event.payload["task_id"] == previous.payload["task_id"]
        default:
            return false
        }
    }
}
