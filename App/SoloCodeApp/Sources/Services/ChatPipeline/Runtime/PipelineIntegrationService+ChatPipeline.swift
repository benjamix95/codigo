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

        if !shouldDebounceRustBridgeOnly(events) {
            flushPendingRustBridgeEventsIfNeeded(
                conversationId: conversationId,
                runtime: runtime,
                chatStore: chatStore
            )
        }

        if shouldDebounceRustBridgeOnly(events), let first = events.first {
            runtime.pendingRustBridgeEvents.append(first)
            scheduleRustBridgeDebounce(for: conversationId)
            return
        }

        runPipelineEventsCommit(
            events: events,
            for: conversationId,
            runtime: runtime,
            chatStore: chatStore
        )
    }

    /// Delta stream singoli: debounce 16ms per raggruppare più `consume` prima del round-trip Rust.
    private func shouldDebounceRustBridgeOnly(_ events: [ChatPipelineEvent]) -> Bool {
        guard events.count == 1, let only = events.first else { return false }
        switch only.kind {
        case .textDelta, .textReplace, .reasoningDelta:
            return true
        default:
            return false
        }
    }

    private func scheduleRustBridgeDebounce(for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        runtime.rustBridgeDebounceTask?.cancel()
        runtime.rustBridgeDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: PipelineConversationRuntime.rustBridgeDebounceNs)
            guard let self, !Task.isCancelled else { return }
            guard let runtime = self.runtime(for: conversationId),
                  let chatStore = self.chatStore else { return }
            self.flushPendingRustBridgeEventsIfNeeded(
                conversationId: conversationId,
                runtime: runtime,
                chatStore: chatStore
            )
        }
    }

    func flushPendingRustBridgeEventsIfNeeded(
        conversationId: UUID,
        runtime: PipelineConversationRuntime,
        chatStore: ChatStore
    ) {
        runtime.rustBridgeDebounceTask?.cancel()
        runtime.rustBridgeDebounceTask = nil
        guard !runtime.pendingRustBridgeEvents.isEmpty else { return }
        let batch = runtime.pendingRustBridgeEvents
        runtime.pendingRustBridgeEvents.removeAll(keepingCapacity: true)
        runPipelineEventsCommit(
            events: batch,
            for: conversationId,
            runtime: runtime,
            chatStore: chatStore
        )
    }

    private func runPipelineEventsCommit(
        events: [ChatPipelineEvent],
        for conversationId: UUID,
        runtime: PipelineConversationRuntime,
        chatStore: ChatStore
    ) {
        PipelineIntegrationConsumeEventsSignpost.measure(eventCount: events.count) {
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

            #if DEBUG
            for sequenced in sequencedEvents where sequenced.kind == .textDelta || sequenced.kind == .textReplace {
                let delta = sequenced.payload["delta"] ?? sequenced.payload["replacement"] ?? ""
                print(
                    "[ChatDebug] pipeline \(sequenced.kind.rawValue): delta=\(delta.count) payload=\(sequenced.payload.keys.sorted().joined(separator: ","))"
                )
            }
            #endif

            var rustAppliedEventCount = 0
            var rustCommitComplete = false
            if applyPipelineEventsThroughRustBoundary(
                sequencedEvents,
                runtime: runtime,
                chatStore: chatStore
            ) {
                rustAppliedEventCount = sequencedEvents.count
                rustCommitComplete = true
            } else if sequencedEvents.count > 1 {
                rustAppliedEventCount = applyPipelineEventsSequentiallyThroughRustBoundary(
                    sequencedEvents,
                    runtime: runtime,
                    chatStore: chatStore
                )
                rustCommitComplete = rustAppliedEventCount == sequencedEvents.count
            }

            if !rustCommitComplete {
                let swiftSuffix = sequencedEvents.dropFirst(rustAppliedEventCount)
                if !swiftSuffix.isEmpty {
                    NSLog(
                        "[PipelineIntegrationService] Rust pipeline incomplete: applied \(rustAppliedEventCount)/\(sequencedEvents.count); Swift fallback \(swiftSuffix.count) events"
                    )
                }
                for sequenced in swiftSuffix {
                    NSLog(
                        "[PipelineIntegrationService] Rust pipeline boundary unavailable for %@, applying Swift fallback",
                        sequenced.kind.rawValue
                    )
                    runtime.chatTurnState = ChatPipelineReducer.apply(
                        state: runtime.chatTurnState,
                        event: sequenced
                    )
                    ChatPipelineCommitter.commit(
                        runtime.chatTurnState,
                        chatStore: chatStore,
                        persistImmediately: false
                    )
                }
            }

            if rustAppliedEventCount > 0 {
                let primarySnapshot = runtime.chatTurnState.primaryTextSnapshot
                if !primarySnapshot.isEmpty {
                    chatStore.reconcileAssistantPrimaryTextFromPipelineIfStoreEmpty(
                        messageId: runtime.assistantMessageId,
                        conversationId: conversationId,
                        primaryText: primarySnapshot,
                        persistImmediately: false
                    )
                }
            }

            if sequencedEvents.contains(where: { $0.kind == .turnCompleted || $0.kind == .turnFailed }) {
                shouldPersistImmediately = true
            }
            let primaryText = runtime.chatTurnState.primaryTextSnapshot
            let textKeys = runtime.chatTurnState.textByStreamId.keys.sorted()
            let streamIds = runtime.chatTurnState.orderedTextStreamIds
            #if DEBUG
            if !primaryText.isEmpty || !coalescedEvents.filter({ $0.kind == .textDelta || $0.kind == .textReplace }).isEmpty {
                print(
                    "[ChatDebug] commit: primaryText=\(primaryText.count) textKeys=\(textKeys.joined(separator: ",")) streamIds=\(streamIds.joined(separator: ",")) blocks=\(runtime.chatTurnState.blocks.count)"
                )
            }
            #endif
            if shouldPersistImmediately {
                chatStore.saveConversationsImmediately()
            } else {
                chatStore.saveConversations()
            }
        }
    }

}
