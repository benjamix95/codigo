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
            // #region agent log
            let hasTextish = sequencedEvents.contains {
                $0.kind == .textDelta || $0.kind == .textReplace
            }
            if hasTextish || !primaryText.isEmpty {
                let kinds = sequencedEvents.map { $0.kind.rawValue }.joined(separator: ",")
                CursorSessionDebugNDJSON.append(
                    hypothesisId: "H2",
                    location: "PipelineIntegrationService+ChatPipeline.swift",
                    message: "pipeline_commit_snapshot",
                    data: [
                        "primaryChars": "\(primaryText.count)",
                        "viaRust": rustCommitComplete ? "1" : "0",
                        "rustApplied": "\(rustAppliedEventCount)",
                        "textStreamKeys": "\(textKeys.count)",
                        "blockCount": "\(runtime.chatTurnState.blocks.count)",
                        "kindsTail": String(kinds.suffix(120)),
                        "conv": String(conversationId.uuidString.prefix(8)),
                    ]
                )
            }
            // #endregion
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

    /// Quando il batch FFI fallisce, stessi eventi applicati uno alla volta (payload più piccoli, stesso contratto Rust).
    private func applyPipelineEventsSequentiallyThroughRustBoundary(
        _ events: [ChatPipelineEvent],
        runtime: PipelineConversationRuntime,
        chatStore: ChatStore
    ) -> Int {
        var applied = 0
        for event in events {
            guard applyPipelineEventThroughRustBoundary(
                event,
                runtime: runtime,
                chatStore: chatStore
            ) else {
                break
            }
            applied += 1
        }
        return applied
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
        let rustStartTime = CFAbsoluteTimeGetCurrent()

        // Use cached store snapshot when available to avoid re-serializing
        // all conversations on every pipeline event. The cache is populated
        // from the Rust boundary response and invalidated on retarget/teardown.
        let storeSnapshot = runtime.cachedStoreSnapshot
            ?? RustMainChatStoreAdapter.snapshot(from: chatStore)
        let taskRuntime = runtime.cachedTaskRuntimeState
            ?? RustMainChatStoreAdapter.taskRuntimeState(from: chatStore)

        let uiState = MainChatUIStateBridge(
            storeSnapshot: storeSnapshot,
            runtimeSnapshot: runtimeSnapshot,
            taskRuntimeState: taskRuntime,
            selectedConversationId: runtime.conversationId.lowercasedString,
            draftText: "",
            planPanelVisible: false,
            followLive: true,
            collapsedArtifactIdsByTurn: [:],
            autoTodoRuntimeStateByMessage: [:]
        )

        guard let first = events.first else { return true }
        let request = MainChatUIIntentRequestBridge(
            intent: "pipeline_apply_events",
            state: uiState,
            conversationId: first.conversationId,
            turnId: first.turnId,
            artifactId: nil,
            text: nil,
            timestamp: events.last?.timestamp,
            pipelineEvent: nil,
            pipelineEvents: events,
            payload: [:]
        )

        guard let response = RustMainChatStoreAdapter.applyUIIntentScopedForPipeline(
            request,
            to: chatStore,
            conversationId: runtime.conversationId
        ), let nextState = response.state?.runtimeSnapshot?.turnState.chatTurnState else {
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - rustStartTime) * 1000)
            if elapsedMs > 100 {
                NSLog("[PipelineIntegrationService] Rust batch boundary took %dms (>100ms threshold), events=%d", elapsedMs, events.count)
            }
            // Invalidate caches on failure — next call will rebuild from store
            runtime.cachedStoreSnapshot = nil
            runtime.cachedTaskRuntimeState = nil
            if events.count == 1 {
                return applyPipelineEventThroughRustBoundary(
                    events[0],
                    runtime: runtime,
                    chatStore: chatStore
                )
            }
            return false
        }
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - rustStartTime) * 1000)
        if elapsedMs > 100 {
            NSLog("[PipelineIntegrationService] Rust batch boundary took %dms (>100ms threshold), events=%d", elapsedMs, events.count)
        }
        runtime.chatTurnState = nextState
        // Cache the updated store snapshot and task runtime from the Rust response
        runtime.cachedStoreSnapshot = response.state?.storeSnapshot
        runtime.cachedTaskRuntimeState = response.state?.taskRuntimeState
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
        let rustStartTime = CFAbsoluteTimeGetCurrent()

        // Use cached store snapshot and task runtime to avoid full re-serialization
        let storeSnapshot = runtime.cachedStoreSnapshot
            ?? RustMainChatStoreAdapter.snapshot(from: chatStore)
        let taskRuntime = runtime.cachedTaskRuntimeState
            ?? RustMainChatStoreAdapter.taskRuntimeState(from: chatStore)

        let uiState = MainChatUIStateBridge(
            storeSnapshot: storeSnapshot,
            runtimeSnapshot: runtimeSnapshot,
            taskRuntimeState: taskRuntime,
            selectedConversationId: runtime.conversationId.lowercasedString,
            draftText: "",
            planPanelVisible: false,
            followLive: true,
            collapsedArtifactIdsByTurn: [:],
            autoTodoRuntimeStateByMessage: [:]
        )

        let request = MainChatUIIntentRequestBridge(
            intent: "pipeline_apply_event",
            state: uiState,
            conversationId: event.conversationId,
            turnId: event.turnId,
            artifactId: nil,
            text: nil,
            timestamp: event.timestamp,
            pipelineEvent: event,
            payload: [:]
        )

        guard let response = RustMainChatStoreAdapter.applyUIIntentScopedForPipeline(
            request,
            to: chatStore,
            conversationId: runtime.conversationId
        ), let nextState = response.state?.runtimeSnapshot?.turnState.chatTurnState else {
            runtime.cachedStoreSnapshot = nil
            runtime.cachedTaskRuntimeState = nil
            return false
        }
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - rustStartTime) * 1000)
        if elapsedMs > 100 {
            NSLog("[PipelineIntegrationService] Rust single-event boundary took %dms (>100ms threshold), kind=%@", elapsedMs, event.kind.rawValue)
        }
        runtime.chatTurnState = nextState
        // Cache the updated store snapshot and task runtime
        runtime.cachedStoreSnapshot = response.state?.storeSnapshot
        runtime.cachedTaskRuntimeState = response.state?.taskRuntimeState
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
            case .reasoningDelta:
                var mergedPayload = last.payload
                let previousChunk = last.payload["output"] ?? last.payload["delta"] ?? ""
                let incomingChunk = event.payload["output"] ?? event.payload["delta"] ?? ""
                let combined = ChatStreamReasoningTextMerge.merge(
                    existing: previousChunk.isEmpty ? nil : previousChunk,
                    incoming: incomingChunk
                )
                mergedPayload["output"] = combined
                mergedPayload.removeValue(forKey: "delta")
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
        case .reasoningDelta:
            return (event.payload["group_id"] ?? "reasoning") == (previous.payload["group_id"] ?? "reasoning")
        default:
            return false
        }
    }
}
