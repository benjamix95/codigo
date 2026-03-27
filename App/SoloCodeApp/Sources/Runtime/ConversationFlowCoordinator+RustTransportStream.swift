import Foundation
import CoderEngine
import os

private let runtimeStreamLogger = Logger(subsystem: "com.solocode.app", category: "RuntimeStream")

extension ConversationFlowCoordinator {
    func runRustTransportStream(
        provider: MainChatRustTransportProvider,
        prompt: String,
        context: WorkspaceContext,
        attachments: [LLMAttachment]?,
        onText: @escaping (String) -> Void,
        onRaw: @escaping (String, [String: String], String) -> Void,
        onError: @escaping (String) -> Void,
        onSignal: ((StreamSignal) -> Void)?,
        runtimeSnapshot: inout MainChatRuntimeSnapshotBridge,
        turnState: inout ChatTurnState
    ) async throws -> String {
        let sessionId = try provider.startRuntimeSession(prompt: prompt, context: context, attachments: attachments)
        return try await withTaskCancellationHandler {
            var hasSeenNarrativeEvent = false
            var didReleaseOperationalFallback = false
            var bufferedRawEvents: [(String, [String: String])] = []
            var queuedRawEvents = ConversationFlowRawEventBatch()
            var firstBufferedOperationalAt: Date? = nil
            var renderedTextSnapshot = turnState.primaryTextSnapshot
            var pendingReasoningSnapshot = ""
            var coalescedAssistantTextDirty = false
            var coalescedAssistantDeltaCount = 0
            var assistantTextLastFlushedLen = renderedTextSnapshot.count
            var assistantTextLastFlushAt = Date()
            var consecutiveEmptyUiPolls = 0
            let bufferedOperationalReleaseDelay: TimeInterval = 1.5
            let bufferedOperationalReleaseCount = 8
            let suppressReasoningUI = ChatReasoningPresentationPolicy.shouldSuppressReasoningUI(
                messageProviderId: nil,
                fallbackTurnProviderId: provider.id
            )
            let shouldFlushNarrativeTextReplaceImmediately = provider.id == "codex-cli"
            let textFlushPolicy = ConversationFlowTextFlushPolicy()
            var claudeReasoningLastFlush = ContinuousClock.now
            var claudeReasoningLastSentLen = 0
            var agentDebugPollWave = 0

            func flushClaudeCliReasoningDelta(force: Bool) async {
                guard provider.id == "claude-cli", !hasSeenNarrativeEvent else { return }
                let snapshot = pendingReasoningSnapshot
                guard !snapshot.isEmpty else { return }
                let now = ContinuousClock.now
                let firstChunk = claudeReasoningLastSentLen == 0
                let grown = snapshot.count - claudeReasoningLastSentLen
                if !force, !firstChunk, grown < 256, now - claudeReasoningLastFlush < .milliseconds(48) { return }
                claudeReasoningLastFlush = now
                claudeReasoningLastSentLen = snapshot.count
                await MainActor.run {
                    onRaw("reasoning", ["output": snapshot, "title": "Thinking", "group_id": "reasoning-stream"], provider.id)
                }
            }

            func flushCoalescedAssistantText() async {
                guard coalescedAssistantTextDirty else { return }
                coalescedAssistantTextDirty = false
                coalescedAssistantDeltaCount = 0
                let textCopy = renderedTextSnapshot
                let flushStartedAt = Date()
                await MainActor.run {
                    RuntimeStreamSignpost.measureMainActorTextFlush { onText(textCopy) }
                }
                assistantTextLastFlushedLen = textCopy.count
                assistantTextLastFlushAt = flushStartedAt
            }

            func emitAssistantTextImmediately() {
                let textCopy = renderedTextSnapshot
                let flushStartedAt = Date()
                coalescedAssistantTextDirty = false
                coalescedAssistantDeltaCount = 0
                DispatchQueue.main.async {
                    RuntimeStreamSignpost.measureMainActorTextFlush { onText(textCopy) }
                }
                assistantTextLastFlushedLen = textCopy.count
                assistantTextLastFlushAt = flushStartedAt
            }

            func flushQueuedRawEvents() async {
                let pending = queuedRawEvents.drain()
                guard !pending.isEmpty else { return }
                await MainActor.run {
                    for (type, payload) in pending {
                        onRaw(type, payload, provider.id)
                    }
                }
            }

            while true {
                try Task.checkCancellation()
                let baseTimeoutMs = max(1, (runtimeSnapshot.currentPollTimeoutSeconds ?? 90) * 1000)
                let adaptiveExtraMs = min(consecutiveEmptyUiPolls * 2_500, 25_000)
                let timeoutMs = min(baseTimeoutMs + adaptiveExtraMs, 600_000)
                let response = RuntimeStreamSignpost.measurePoll(timeoutMs: timeoutMs) {
                    provider.pollRuntime(sessionId: sessionId, providerId: provider.id, snapshot: runtimeSnapshot, timeoutMs: timeoutMs)
                }

                guard let response, let nextSnapshot = response.runtimeSnapshot else {
                    await setState(.error)
                    throw StreamExecutionError.providerError("Rust main chat provider runtime poll unavailable.")
                }

                try Task.checkCancellation()
                runtimeSnapshot = nextSnapshot
                setDirectRuntimeSnapshot(nextSnapshot)
                turnState = nextSnapshot.turnState.chatTurnState
                consecutiveEmptyUiPolls = response.uiEvents.isEmpty && !response.isTerminal ? (consecutiveEmptyUiPolls + 1) : 0
                let eventTimestamp = Date()

                // MARK: Agent debug ingest
                agentDebugPollWave += 1
                if agentDebugPollWave <= 5 {
                    let kinds = response.uiEvents.map(\.kind.rawValue).joined(separator: ",")
                    let errMsg = response.error.map { String($0.message.prefix(300)) } ?? ""
                    AgentDebugIngestLog.append(
                        hypothesisId: "H1",
                        location: "ConversationFlowCoordinator+RustTransportStream.poll",
                        message: "poll_wave",
                        data: [
                            "wave": "\(agentDebugPollWave)",
                            "provider": provider.id,
                            "isTerminal": response.isTerminal ? "1" : "0",
                            "didTimeout": response.didTimeout ? "1" : "0",
                            "uiCount": "\(response.uiEvents.count)",
                            "kinds": String(kinds.prefix(500)),
                            "pollErr": errMsg,
                            "hasSnap": response.runtimeSnapshot != nil ? "1" : "0",
                        ]
                    )
                }

                for signal in response.signals {
                    await MainActor.run {
                        switch signal {
                        case .firstEvent: onSignal?(.firstEvent(eventTimestamp))
                        case .firstTextDelta: onSignal?(.firstTextDelta(eventTimestamp))
                        case .streamCompleted: onSignal?(.streamCompleted(eventTimestamp))
                        }
                    }
                }

                for event in response.uiEvents {
                    try Task.checkCancellation()
                    switch event.kind {
                    case .started:
                        await flushQueuedRawEvents()
                    case .textDelta:
                        await flushQueuedRawEvents()
                        if !hasSeenNarrativeEvent && provider.id == "claude-cli" {
                            pendingReasoningSnapshot += event.text
                            await flushClaudeCliReasoningDelta(force: false)
                            continue
                        }
                        hasSeenNarrativeEvent = true
                        renderedTextSnapshot += event.text
                        coalescedAssistantTextDirty = true
                        coalescedAssistantDeltaCount += 1
                    case .textReplace:
                        await flushQueuedRawEvents()
                        if !hasSeenNarrativeEvent && provider.id == "claude-cli" {
                            pendingReasoningSnapshot = event.text
                            await flushClaudeCliReasoningDelta(force: true)
                        } else {
                            hasSeenNarrativeEvent = true
                            renderedTextSnapshot = event.text
                            coalescedAssistantTextDirty = true
                            coalescedAssistantDeltaCount += 1
                            if shouldFlushNarrativeTextReplaceImmediately {
                                emitAssistantTextImmediately()
                                await flushQueuedRawEvents()
                                if !bufferedRawEvents.isEmpty {
                                    queuedRawEvents.append(contentsOf: bufferedRawEvents)
                                    bufferedRawEvents.removeAll(keepingCapacity: true)
                                    firstBufferedOperationalAt = nil
                                    await flushQueuedRawEvents()
                                }
                                continue
                            }
                        }
                        await flushCoalescedAssistantText()
                        if !bufferedRawEvents.isEmpty {
                            queuedRawEvents.append(contentsOf: bufferedRawEvents)
                            bufferedRawEvents.removeAll(keepingCapacity: true)
                            firstBufferedOperationalAt = nil
                        }
                        await flushQueuedRawEvents()
                    case .raw:
                        let rawType = event.rawType ?? "provider_raw"
                        if textFlushPolicy.shouldFlushBeforeRawEvent(
                            isDirty: coalescedAssistantTextDirty,
                            renderedTextCount: renderedTextSnapshot.count,
                            lastFlushedLength: assistantTextLastFlushedLen,
                            lastFlushAt: assistantTextLastFlushAt
                        ) {
                            await flushCoalescedAssistantText()
                        }
                        if rawType == "reasoning", suppressReasoningUI { continue }
                        if rawType == "reasoning", runtimeStreamLogger.isEnabled(type: .debug) {
                            runtimeStreamLogger.debug(
                                ".raw reasoning keys=\(event.payload.keys.sorted(), privacy: .public) hasSeenNarrative=\(hasSeenNarrativeEvent, privacy: .public)"
                            )
                        }
                        if rawType == "assistant_update" || rawType == "reasoning" {
                            if !pendingReasoningSnapshot.isEmpty {
                                await flushClaudeCliReasoningDelta(force: true)
                                pendingReasoningSnapshot = ""
                                claudeReasoningLastSentLen = 0
                            }
                            if rawType == "reasoning" || !suppressReasoningUI {
                                hasSeenNarrativeEvent = true
                            }
                        }
                        if !hasSeenNarrativeEvent
                            && !didReleaseOperationalFallback
                            && shouldBufferOperationalRawEventUntilNarrative(rawType: rawType, payload: event.payload)
                        {
                            if firstBufferedOperationalAt == nil {
                                firstBufferedOperationalAt = eventTimestamp
                            }
                            bufferedRawEvents.append((rawType, event.payload))
                            let shouldReleaseBufferedFallback =
                                bufferedRawEvents.count >= bufferedOperationalReleaseCount
                                || eventTimestamp.timeIntervalSince(firstBufferedOperationalAt ?? eventTimestamp) >= bufferedOperationalReleaseDelay
                            if shouldReleaseBufferedFallback {
                                queuedRawEvents.append(contentsOf: bufferedRawEvents)
                                bufferedRawEvents.removeAll(keepingCapacity: true)
                                firstBufferedOperationalAt = nil
                                didReleaseOperationalFallback = true
                            }
                            continue
                        }

                        if rawType == "reasoning", runtimeStreamLogger.isEnabled(type: .debug) {
                            runtimeStreamLogger.debug("forwarding reasoning to onRaw")
                        }
                        queuedRawEvents.append((rawType, event.payload))
                        if hasSeenNarrativeEvent, !bufferedRawEvents.isEmpty {
                            queuedRawEvents.append(contentsOf: bufferedRawEvents)
                            bufferedRawEvents.removeAll(keepingCapacity: true)
                            firstBufferedOperationalAt = nil
                        }
                    case .error:
                        await flushCoalescedAssistantText()
                        await flushQueuedRawEvents()
                        if !bufferedRawEvents.isEmpty {
                            queuedRawEvents.append(contentsOf: bufferedRawEvents)
                            bufferedRawEvents.removeAll(keepingCapacity: true)
                        }
                        await flushQueuedRawEvents()
                        let message = event.text.isEmpty
                            ? (runtimeSnapshot.output?.terminalError ?? "Provider stream failed")
                            : event.text
                        let textSnapshot = renderedTextSnapshot.isEmpty ? turnState.primaryTextSnapshot : renderedTextSnapshot
                        await MainActor.run { onError(textSnapshot + "\n\n[Error: \(message)]") }
                        await setState(.error)
                        // MARK: Agent debug ingest
                        AgentDebugIngestLog.append(
                            hypothesisId: "H1",
                            location: "ConversationFlowCoordinator+RustTransportStream.ui_event",
                            message: "ui_error_event",
                            data: [
                                "provider": provider.id,
                                "msg": String(message.prefix(400)),
                                "renderedLen": "\(renderedTextSnapshot.count)",
                            ]
                        )
                        throw StreamExecutionError.providerError(message)
                    case .completed:
                        await flushCoalescedAssistantText()
                        if !bufferedRawEvents.isEmpty {
                            queuedRawEvents.append(contentsOf: bufferedRawEvents)
                            bufferedRawEvents.removeAll(keepingCapacity: true)
                        }
                        await flushQueuedRawEvents()
                        await setState(.completed)
                        // MARK: Agent debug ingest
                        let outLen = renderedTextSnapshot.isEmpty ? turnState.primaryTextSnapshot.count : renderedTextSnapshot.count
                        AgentDebugIngestLog.append(
                            hypothesisId: "H1",
                            location: "ConversationFlowCoordinator+RustTransportStream.ui_event",
                            message: "ui_completed",
                            data: [
                                "provider": provider.id,
                                "renderedLen": "\(renderedTextSnapshot.count)",
                                "turnPrimaryLen": "\(turnState.primaryTextSnapshot.count)",
                                "outLen": "\(outLen)",
                                "pollWave": "\(agentDebugPollWave)",
                            ]
                        )
                        return renderedTextSnapshot.isEmpty ? turnState.primaryTextSnapshot : renderedTextSnapshot
                    }
                }

                await flushCoalescedAssistantText()
                await flushQueuedRawEvents()
                await Task.yield()
            }
        } onCancel: {
            provider.cancelRuntimeSession(sessionId: sessionId)
        }
    }
}
