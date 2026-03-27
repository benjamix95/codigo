import CoderEngine
import Foundation

extension PipelineIntegrationService {
    /// Quando il batch FFI fallisce, stessi eventi applicati uno alla volta (payload più piccoli, stesso contratto Rust).
    func applyPipelineEventsSequentiallyThroughRustBoundary(
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

    func applyPipelineEventsThroughRustBoundary(
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
        let storeSnapshot = runtime.cachedStoreSnapshot
            ?? RustMainChatStoreAdapter.scopedSnapshot(
                from: chatStore,
                conversationIds: Set([runtime.conversationId]),
                planBoardConversationIds: runtime.planConversationId.map { Set([$0]) } ?? []
            )
        let taskRuntime = runtime.cachedTaskRuntimeState
            ?? RustMainChatStoreAdapter.taskRuntimeState(from: chatStore)

        guard let first = events.first else { return true }
        let request = MainChatUIIntentRequestBridge(
            intent: "pipeline_apply_events",
            state: RustMainChatStoreAdapter.scopedPipelineUIState(
                storeSnapshot: storeSnapshot,
                context: .pipeline(
                    runtimeSnapshot: runtimeSnapshot,
                    conversationId: runtime.conversationId
                ),
                taskRuntimeState: taskRuntime
            ),
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
        runtime.cachedStoreSnapshot = response.state?.storeSnapshot
        runtime.cachedTaskRuntimeState = response.state?.taskRuntimeState
        return true
    }

    func applyPipelineEventThroughRustBoundary(
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
        let storeSnapshot = runtime.cachedStoreSnapshot
            ?? RustMainChatStoreAdapter.scopedSnapshot(
                from: chatStore,
                conversationIds: Set([runtime.conversationId]),
                planBoardConversationIds: runtime.planConversationId.map { Set([$0]) } ?? []
            )
        let taskRuntime = runtime.cachedTaskRuntimeState
            ?? RustMainChatStoreAdapter.taskRuntimeState(from: chatStore)

        let request = MainChatUIIntentRequestBridge(
            intent: "pipeline_apply_event",
            state: RustMainChatStoreAdapter.scopedPipelineUIState(
                storeSnapshot: storeSnapshot,
                context: .pipeline(
                    runtimeSnapshot: runtimeSnapshot,
                    conversationId: runtime.conversationId
                ),
                taskRuntimeState: taskRuntime
            ),
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
        runtime.cachedStoreSnapshot = response.state?.storeSnapshot
        runtime.cachedTaskRuntimeState = response.state?.taskRuntimeState
        return true
    }

    func coalescePipelineEvents(_ events: [ChatPipelineEvent]) -> [ChatPipelineEvent] {
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

    func canCoalescePipelineEvent(
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
