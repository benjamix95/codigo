import Foundation
import CoderEngine
import os

func shouldBufferOperationalRawEventUntilNarrative(
    rawType: String,
    payload: [String: String]
) -> Bool {
    let type = rawType
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if type.isEmpty { return false }

    let nonBufferedTypes: Set<String> = [
        "started",
        "turn_started",
        "turn_completed",
        "policy_ack",
        "assistant_update",
        "reasoning",
        "error",
        "tool_validation_error",
        "tool_execution_error",
        "tool_timeout",
        "permission_denied",
        "usage",
    ]
    if nonBufferedTypes.contains(type) { return false }
    if type.hasPrefix("reasoning") || type.hasPrefix("thinking") { return false }

    if type == "mcp_tool_call" {
        let tool = (payload["mcp_tool"] ?? payload["tool"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedTool = tool
            .replacingOccurrences(of: "functions.", with: "")
            .replacingOccurrences(of: "function.", with: "")
        if normalizedTool == "coderide_policy_ack" || normalizedTool == "policy_ack" {
            return false
        }
    }

    if type == "mcp_tool_call" || type == "command_execution" || type == "bash" {
        return true
    }
    if type == "agent"
        || type == "read"
        || type == "read_range"
        || type == "grep"
        || type == "glob"
        || type == "codebase_search"
        || type == "find_symbol"
        || type == "find_references"
        || type == "file_outline"
        || type == "list_dir"
    {
        return true
    }
    if type.hasPrefix("web_search")
        || type.hasPrefix("web_fetch")
        || type.hasPrefix("todo_")
        || type.hasPrefix("plan_")
        || type == "search"
        || type == "semantic_search"
        || type == "instant_grep"
        || type == "file_change"
        || type == "edit"
        || type == "skill_invocation"
    {
        return true
    }

    return ToolTraceVisibility.requiresPolicyAck(type: type, payload: payload)
}

private let runtimeStreamLogger = Logger(subsystem: "com.solocode.app", category: "RuntimeStream")

/// Legacy flow coordinator retained as a Swift adapter around the Rust-backed
/// direct stream runtime while provider transport remains in Swift.
final class ConversationFlowCoordinator: ObservableObject {
    enum StreamExecutionError: LocalizedError {
        case providerError(String)

        var errorDescription: String? {
            switch self {
            case .providerError(let message):
                return message
            }
        }
    }

    let initialEventTimeoutOverride: Int?
    let activityTimeoutOverride: Int?
    let initialRetryOverride: Int?
    let stallRetryOverride: Int?
    var directRuntimeSnapshot: MainChatRuntimeSnapshotBridge?
    var planRuntimeSnapshot: MainChatRuntimeSnapshotBridge?

    init(
        initialEventTimeoutOverride: Int? = nil,
        activityTimeoutOverride: Int? = nil,
        initialRetryOverride: Int? = nil,
        stallRetryOverride: Int? = nil
    ) {
        self.initialEventTimeoutOverride = initialEventTimeoutOverride
        self.activityTimeoutOverride = activityTimeoutOverride
        self.initialRetryOverride = initialRetryOverride
        self.stallRetryOverride = stallRetryOverride
    }

    enum StreamSignal {
        case streamStarted(Date)
        case firstEvent(Date)
        case firstTextDelta(Date)
        case streamCompleted(Date)
    }

    enum State: String {
        case idle
        case streaming
        case completed
        case error
        case interrupted
    }

    @Published private(set) var state: State = .idle

    @MainActor
    func startStreaming() { state = .streaming }

    @MainActor
    func finish() { state = .completed }

    @MainActor
    func fail() { state = .error }

    @MainActor
    func interrupt() { state = .interrupted }

    @MainActor
    func reset() { state = .idle }

    func normalizeRawEvent(
        providerId: String,
        type: String,
        payload: [String: String],
        timestamp: Date = .now
    ) -> NormalizedEventEnvelope {
        EventNormalizer.normalizeEnvelope(
            sourceProvider: providerId,
            type: type,
            payload: payload,
            timestamp: timestamp
        )
    }

    func directRuntimeSnapshotState() -> MainChatRuntimeSnapshotBridge? { directRuntimeSnapshot }
    func setDirectRuntimeSnapshot(_ snapshot: MainChatRuntimeSnapshotBridge?) { directRuntimeSnapshot = snapshot }
    func planRuntimeSnapshotState() -> MainChatRuntimeSnapshotBridge? { planRuntimeSnapshot }
    func setPlanRuntimeSnapshot(_ snapshot: MainChatRuntimeSnapshotBridge?) { planRuntimeSnapshot = snapshot }

    private func setState(_ newState: State) async {
        await MainActor.run { state = newState }
    }

    func runStream(
        provider: any LLMProvider,
        prompt: String,
        context: WorkspaceContext,
        attachments: [LLMAttachment]?,
        onText: @escaping (String) -> Void,
        onRaw: @escaping (String, [String: String], String) -> Void,
        onError: @escaping (String) -> Void,
        onSignal: ((StreamSignal) -> Void)? = nil
    ) async throws -> String {
        let streamStartedAt = Date()
        await setState(.streaming)

        guard let directRuntimeStart = startDirectRuntime(
            providerId: provider.id,
            turnId: provider.id,
            timestamp: streamStartedAt
        ) else {
            await setState(.error)
            throw StreamExecutionError.providerError("Rust main chat direct stream runtime unavailable.")
        }

        setDirectRuntimeSnapshot(directRuntimeStart)
        var runtimeSnapshot = directRuntimeStart
        var turnState = directRuntimeStart.turnState.chatTurnState
        await MainActor.run { onSignal?(.streamStarted(streamStartedAt)) }

        if let rustProvider = provider as? MainChatRustTransportProvider {
            return try await runRustTransportStream(
                provider: rustProvider,
                prompt: prompt,
                context: context,
                attachments: attachments,
                onText: onText,
                onRaw: onRaw,
                onError: onError,
                onSignal: onSignal,
                runtimeSnapshot: &runtimeSnapshot,
                turnState: &turnState
            )
        }

        await setState(.error)
        throw StreamExecutionError.providerError(
            "Legacy generic stream coordinator path retired for main chat runtime."
        )
    }

    private func runRustTransportStream(
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
        let sessionId = try provider.startRuntimeSession(
            prompt: prompt,
            context: context,
            attachments: attachments
        )
        return try await withTaskCancellationHandler {
            var hasSeenNarrativeEvent = false
            var didReleaseOperationalFallback = false
            var bufferedRawEvents: [(String, [String: String])] = []
            var firstBufferedOperationalAt: Date? = nil
            var renderedTextSnapshot = turnState.primaryTextSnapshot
            var pendingReasoningSnapshot = ""
            var coalescedAssistantTextDirty = false
            var coalescedAssistantDeltaCount = 0
            var assistantTextLastFlushedLen = renderedTextSnapshot.count
            var assistantTextLastFlushAt = Date()
            var consecutiveEmptyUiPolls = 0
            var currentPollTextFlushCount = 0
            var currentPollTextFlushMainActorTotalMs = 0
            var currentPollTextFlushMainActorMaxMs = 0
            var lastPollCycleCompletedAt = Date()
            let bufferedOperationalReleaseDelay: TimeInterval = 1.5
            let bufferedOperationalReleaseCount = 8
            let suppressReasoningUI = ChatReasoningPresentationPolicy.shouldSuppressReasoningUI(
                messageProviderId: nil,
                fallbackTurnProviderId: provider.id
            )
            let shouldFlushNarrativeTextDeltaImmediately = false
            let shouldFlushNarrativeTextReplaceImmediately = provider.id == "codex-cli"
            // #region agent log
            RuntimeEvidenceDebugLog.append(
                hypothesisId: "H24",
                location: "ConversationFlowCoordinator.runRustTransportStream",
                message: "codex_text_delta_flush_mode",
                data: [
                    "providerId": provider.id,
                    "shouldFlushNarrativeTextDeltaImmediately": "\(shouldFlushNarrativeTextDeltaImmediately)",
                    "shouldFlushNarrativeTextReplaceImmediately": "\(shouldFlushNarrativeTextReplaceImmediately)",
                ]
            )
            // #endregion
            /// Riduce hop MainActor per thinking Claude CLI (delta densi).
            var claudeReasoningLastFlush = ContinuousClock.now
            var claudeReasoningLastSentLen = 0
            func flushClaudeCliReasoningDelta(force: Bool) async {
                guard provider.id == "claude-cli", !hasSeenNarrativeEvent else { return }
                let snapshot = pendingReasoningSnapshot
                guard !snapshot.isEmpty else { return }
                let now = ContinuousClock.now
                let firstChunk = claudeReasoningLastSentLen == 0
                let grown = snapshot.count - claudeReasoningLastSentLen
                let since = now - claudeReasoningLastFlush
                if !force, !firstChunk, grown < 256, since < .milliseconds(48) { return }
                claudeReasoningLastFlush = now
                claudeReasoningLastSentLen = snapshot.count
                let reasoningCopy = snapshot
                await MainActor.run {
                    onRaw(
                        "reasoning",
                        [
                            "output": reasoningCopy,
                            "title": "Thinking",
                            "group_id": "reasoning-stream",
                        ],
                        provider.id
                    )
                }
            }
            func flushCoalescedAssistantText(reason: String) async {
                guard coalescedAssistantTextDirty else { return }
                coalescedAssistantTextDirty = false
                let textCopy = renderedTextSnapshot
                let flushStartedAt = Date()
                let bufferedDeltaCount = coalescedAssistantDeltaCount
                let charsSinceLastFlush = max(0, textCopy.count - assistantTextLastFlushedLen)
                let msSinceLastFlush = Int(flushStartedAt.timeIntervalSince(assistantTextLastFlushAt) * 1000)
                coalescedAssistantDeltaCount = 0
                let mainActorFlushStartedAt = Date()
                await MainActor.run {
                    RuntimeStreamSignpost.measureMainActorTextFlush {
                        onText(textCopy)
                    }
                }
                let mainActorFlushMs = Int(Date().timeIntervalSince(mainActorFlushStartedAt) * 1000)
                currentPollTextFlushCount += 1
                currentPollTextFlushMainActorTotalMs += mainActorFlushMs
                currentPollTextFlushMainActorMaxMs = max(currentPollTextFlushMainActorMaxMs, mainActorFlushMs)
                // #region agent log
                RuntimeEvidenceDebugLog.append(
                    hypothesisId: "H22",
                    location: "ConversationFlowCoordinator.runRustTransportStream",
                    message: "assistant_text_flush_to_ui",
                    data: [
                        "providerId": provider.id,
                        "reason": reason,
                        "totalLen": "\(textCopy.count)",
                        "charsSinceLastFlush": "\(charsSinceLastFlush)",
                        "bufferedDeltaCount": "\(bufferedDeltaCount)",
                        "msSinceLastFlush": "\(msSinceLastFlush)",
                        "mainActorFlushMs": "\(mainActorFlushMs)",
                        "hasSeenNarrativeEvent": "\(hasSeenNarrativeEvent)",
                    ]
                )
                // #endregion
                assistantTextLastFlushedLen = textCopy.count
                assistantTextLastFlushAt = flushStartedAt
            }
            func emitAssistantTextImmediately(reason: String) async {
                let textCopy = renderedTextSnapshot
                let flushStartedAt = Date()
                let bufferedDeltaCount = max(1, coalescedAssistantDeltaCount)
                let charsSinceLastFlush = max(0, textCopy.count - assistantTextLastFlushedLen)
                let msSinceLastFlush = Int(flushStartedAt.timeIntervalSince(assistantTextLastFlushAt) * 1000)
                coalescedAssistantTextDirty = false
                coalescedAssistantDeltaCount = 0
                let mainActorEnqueueStartedAt = Date()
                DispatchQueue.main.async {
                    let dispatchDelayMs = Int(Date().timeIntervalSince(mainActorEnqueueStartedAt) * 1000)
                    // #region agent log
                    RuntimeEvidenceDebugLog.appendThrottled(
                        gateKey: "H36-main-async-ontext-\(provider.id)-\(sessionId)",
                        minInterval: 0.08,
                        hypothesisId: "H36",
                        location: "ConversationFlowCoordinator.runRustTransportStream",
                        message: "onText_main_queue_dispatch_executed",
                        data: [
                            "providerId": provider.id,
                            "reason": reason,
                            "dispatchDelayMs": "\(dispatchDelayMs)",
                            "textLen": "\(textCopy.count)",
                            "hasSeenNarrativeEvent": "\(hasSeenNarrativeEvent)",
                        ]
                    )
                    // #endregion
                    RuntimeStreamSignpost.measureMainActorTextFlush {
                        onText(textCopy)
                    }
                }
                let mainActorFlushMs = Int(Date().timeIntervalSince(mainActorEnqueueStartedAt) * 1000)
                currentPollTextFlushCount += 1
                currentPollTextFlushMainActorTotalMs += mainActorFlushMs
                currentPollTextFlushMainActorMaxMs = max(currentPollTextFlushMainActorMaxMs, mainActorFlushMs)
                // #region agent log
                RuntimeEvidenceDebugLog.append(
                    hypothesisId: "H22",
                    location: "ConversationFlowCoordinator.runRustTransportStream",
                    message: "assistant_text_flush_to_ui",
                    data: [
                        "providerId": provider.id,
                        "reason": reason,
                        "totalLen": "\(textCopy.count)",
                        "charsSinceLastFlush": "\(charsSinceLastFlush)",
                        "bufferedDeltaCount": "\(bufferedDeltaCount)",
                        "msSinceLastFlush": "\(msSinceLastFlush)",
                        "mainActorFlushMs": "\(mainActorFlushMs)",
                        "mainActorFlushMode": "fire_and_forget",
                        "hasSeenNarrativeEvent": "\(hasSeenNarrativeEvent)",
                    ]
                )
                // #endregion
                assistantTextLastFlushedLen = textCopy.count
                assistantTextLastFlushAt = flushStartedAt
            }
            func forwardRawEventsOnMainActor(_ events: [(String, [String: String])]) async {
                guard !events.isEmpty else { return }
                let pid = provider.id
                await MainActor.run {
                    for (t, pl) in events {
                        onRaw(t, pl, pid)
                    }
                }
            }
            while true {
                try Task.checkCancellation()
                let pollCycleStartedAt = Date()
                let msSincePreviousCycleCompleted = Int(
                    pollCycleStartedAt.timeIntervalSince(lastPollCycleCompletedAt) * 1000
                )
                let baseTimeoutMs = max(1, (runtimeSnapshot.currentPollTimeoutSeconds ?? 90) * 1000)
                let adaptiveExtraMs = min(consecutiveEmptyUiPolls * 2_500, 25_000)
                let timeoutMs = min(baseTimeoutMs + adaptiveExtraMs, 600_000)
                let response = RuntimeStreamSignpost.measurePoll(timeoutMs: timeoutMs) {
                    provider.pollRuntime(
                        sessionId: sessionId,
                        providerId: provider.id,
                        snapshot: runtimeSnapshot,
                        timeoutMs: timeoutMs
                    )
                }
                let pollReturnedAt = Date()
                currentPollTextFlushCount = 0
                currentPollTextFlushMainActorTotalMs = 0
                currentPollTextFlushMainActorMaxMs = 0
                guard let response, let nextSnapshot = response.runtimeSnapshot else {
                    await setState(.error)
                    throw StreamExecutionError.providerError("Rust main chat provider runtime poll unavailable.")
                }

                try Task.checkCancellation()
                runtimeSnapshot = nextSnapshot
                setDirectRuntimeSnapshot(nextSnapshot)
                turnState = nextSnapshot.turnState.chatTurnState
                if response.uiEvents.isEmpty, !response.isTerminal {
                    consecutiveEmptyUiPolls += 1
                    // #region agent log
                    RuntimeEvidenceDebugLog.appendThrottled(
                        gateKey: "H2-empty-poll-\(provider.id)-\(sessionId)",
                        minInterval: 1.2,
                        hypothesisId: "H2",
                        location: "ConversationFlowCoordinator.runRustTransportStream",
                        message: "empty_poll_before_visible_progress",
                        data: [
                            "providerId": provider.id,
                            "timeoutMs": "\(timeoutMs)",
                            "consecutiveEmptyUiPolls": "\(consecutiveEmptyUiPolls)",
                            "hasReceivedAnyEvent": "\(nextSnapshot.directStream?.hasReceivedAnyEvent ?? false)",
                            "emittedFirstText": "\(nextSnapshot.directStream?.emittedFirstText ?? false)",
                        ]
                    )
                    // #endregion
                } else {
                    consecutiveEmptyUiPolls = 0
                }
                let eventTimestamp = Date()
                var pollTextDeltaCount = 0
                var pollTextReplaceCount = 0
                var pollRawCount = 0

                for signal in response.signals {
                    // #region agent log
                    RuntimeEvidenceDebugLog.append(
                        hypothesisId: "H2",
                        location: "ConversationFlowCoordinator.runRustTransportStream",
                        message: "runtime_signal",
                        data: [
                            "providerId": provider.id,
                            "signal": "\(signal)",
                            "hasReceivedAnyEvent": "\(nextSnapshot.directStream?.hasReceivedAnyEvent ?? false)",
                            "emittedFirstText": "\(nextSnapshot.directStream?.emittedFirstText ?? false)",
                        ]
                    )
                    // #endregion
                    await MainActor.run {
                        switch signal {
                        case .firstEvent:
                            onSignal?(.firstEvent(eventTimestamp))
                        case .firstTextDelta:
                            onSignal?(.firstTextDelta(eventTimestamp))
                        case .streamCompleted:
                            onSignal?(.streamCompleted(eventTimestamp))
                        }
                    }
                }

                for event in response.uiEvents {
                    try Task.checkCancellation()
                    switch event.kind {
                    case .started:
                        break
                    case .textDelta:
                        pollTextDeltaCount += 1
                        // For non-Claude CLI providers (Codex, Kilo, API providers),
                        // textDelta is always real text, not reasoning that arrives
                        // before a narrative marker. Only route to reasoning for
                        // Claude CLI which emits thinking blocks as textDelta before
                        // the assistant_update event.
                        let isClaudeCli = provider.id == "claude-cli"
                        if !hasSeenNarrativeEvent && isClaudeCli {
                            pendingReasoningSnapshot += event.text
                            await flushClaudeCliReasoningDelta(force: false)
                        } else {
                            hasSeenNarrativeEvent = true
                            renderedTextSnapshot += event.text
                            coalescedAssistantTextDirty = true
                            coalescedAssistantDeltaCount += 1
                            if shouldFlushNarrativeTextDeltaImmediately {
                                // #region agent log
                                RuntimeEvidenceDebugLog.appendThrottled(
                                    gateKey: "H24-text-delta-branch-\(provider.id)-\(sessionId)",
                                    minInterval: 0.25,
                                    hypothesisId: "H24",
                                    location: "ConversationFlowCoordinator.runRustTransportStream",
                                    message: "text_delta_immediate_flush_branch_taken",
                                    data: [
                                        "providerId": provider.id,
                                        "renderedLen": "\(renderedTextSnapshot.count)",
                                        "deltaLen": "\(event.text.count)",
                                    ]
                                )
                                // #endregion
                                await emitAssistantTextImmediately(reason: "text_delta")
                            }
                        }
                    case .textReplace:
                        pollTextReplaceCount += 1
                        let isClaudeCliReplace = provider.id == "claude-cli"
                        if !hasSeenNarrativeEvent && isClaudeCliReplace {
                            pendingReasoningSnapshot = event.text
                            await flushClaudeCliReasoningDelta(force: true)
                        } else {
                            hasSeenNarrativeEvent = true
                            renderedTextSnapshot = event.text
                            coalescedAssistantTextDirty = true
                            coalescedAssistantDeltaCount += 1
                            if shouldFlushNarrativeTextReplaceImmediately {
                                await emitAssistantTextImmediately(reason: "text_replace")
                                if !bufferedRawEvents.isEmpty {
                                    let pending = bufferedRawEvents
                                    bufferedRawEvents.removeAll(keepingCapacity: true)
                                    await forwardRawEventsOnMainActor(pending)
                                }
                                continue
                            }
                        }
                        await flushCoalescedAssistantText(reason: "text_replace")
                        if !bufferedRawEvents.isEmpty {
                            let pending = bufferedRawEvents
                            bufferedRawEvents.removeAll(keepingCapacity: true)
                            await forwardRawEventsOnMainActor(pending)
                        }
                    case .raw:
                        pollRawCount += 1
                        await flushCoalescedAssistantText(reason: "raw_event")
                        let rawType = event.rawType ?? "provider_raw"
                        let rawOutput = event.payload["output"] ?? event.payload["text"] ?? ""
                        let rawDetail = event.payload["detail"] ?? ""
                        let rawStatus = event.payload["status"] ?? ""
                        let rawTitle = event.payload["title"] ?? ""
                        let statusJSON = event.payload["status_json"] ?? ""
                        let outputPreview = String(rawOutput.prefix(160))
                        let detailPreview = String(rawDetail.prefix(160))
                        let statusJSONPreview = String(statusJSON.prefix(200))
                        // #region agent log
                        RuntimeEvidenceDebugLog.appendThrottled(
                            gateKey: "H10-raw-\(provider.id)-\(rawType)",
                            minInterval: 0.35,
                            hypothesisId: "H10",
                            location: "ConversationFlowCoordinator.runRustTransportStream",
                            message: "runtime_raw_event",
                            data: [
                                "providerId": provider.id,
                                "rawType": rawType,
                                "hasSeenNarrativeEvent": "\(hasSeenNarrativeEvent)",
                                "payloadKeys": event.payload.keys.sorted().joined(separator: ","),
                                "title": rawTitle,
                                "status": rawStatus,
                                "detailPreview": detailPreview,
                                "outputChars": "\(rawOutput.count)",
                                "outputPreview": outputPreview,
                                "statusJSONChars": "\(statusJSON.count)",
                                "statusJSONPreview": statusJSONPreview,
                            ]
                        )
                        // #endregion
                        if rawType == "reasoning", suppressReasoningUI {
                            continue
                        }
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
                            // #region agent log
                            RuntimeEvidenceDebugLog.appendThrottled(
                                gateKey: "H14-buffered-\(provider.id)-\(rawType)",
                                minInterval: 0.35,
                                hypothesisId: "H14",
                                location: "ConversationFlowCoordinator.runRustTransportStream",
                                message: "runtime_raw_buffered_before_narrative",
                                data: [
                                    "providerId": provider.id,
                                    "rawType": rawType,
                                    "bufferedCount": "\(bufferedRawEvents.count)",
                                    "hasSeenNarrativeEvent": "\(hasSeenNarrativeEvent)",
                                    "outputChars": "\(rawOutput.count)",
                                    "detailPreview": detailPreview,
                                ]
                            )
                            // #endregion
                            let shouldReleaseBufferedFallback: Bool = {
                                if bufferedRawEvents.count >= bufferedOperationalReleaseCount {
                                    return true
                                }
                                guard let firstBufferedOperationalAt else { return false }
                                return eventTimestamp.timeIntervalSince(firstBufferedOperationalAt)
                                    >= bufferedOperationalReleaseDelay
                            }()
                            if shouldReleaseBufferedFallback {
                                let pending = bufferedRawEvents
                                bufferedRawEvents.removeAll(keepingCapacity: true)
                                firstBufferedOperationalAt = nil
                                didReleaseOperationalFallback = true
                                // #region agent log
                                RuntimeEvidenceDebugLog.append(
                                    hypothesisId: "H18",
                                    location: "ConversationFlowCoordinator.runRustTransportStream",
                                    message: "runtime_raw_released_without_narrative",
                                    data: [
                                        "providerId": provider.id,
                                        "releasedCount": "\(pending.count)",
                                        "rawType": rawType,
                                        "hasSeenNarrativeEvent": "\(hasSeenNarrativeEvent)",
                                    ]
                                )
                                // #endregion
                                await forwardRawEventsOnMainActor(pending)
                            }
                        } else {
                            if rawType == "reasoning", runtimeStreamLogger.isEnabled(type: .debug) {
                                runtimeStreamLogger.debug("forwarding reasoning to onRaw")
                            }
                            var batch: [(String, [String: String])] = [(rawType, event.payload)]
                            if hasSeenNarrativeEvent, !bufferedRawEvents.isEmpty {
                                batch.append(contentsOf: bufferedRawEvents)
                                bufferedRawEvents.removeAll(keepingCapacity: true)
                                firstBufferedOperationalAt = nil
                            }
                            await forwardRawEventsOnMainActor(batch)
                        }
                    case .error:
                        await flushCoalescedAssistantText(reason: "error_event")
                        let message = event.text.isEmpty
                            ? (runtimeSnapshot.output?.terminalError ?? "Provider stream failed")
                            : event.text
                        let textSnapshot = renderedTextSnapshot.isEmpty ? turnState.primaryTextSnapshot : renderedTextSnapshot
                        if !bufferedRawEvents.isEmpty {
                            let pending = bufferedRawEvents
                            bufferedRawEvents.removeAll(keepingCapacity: true)
                            await forwardRawEventsOnMainActor(pending)
                        }
                        // #region agent log
                        RuntimeEvidenceDebugLog.append(
                            hypothesisId: "H8",
                            location: "ConversationFlowCoordinator.runRustTransportStream",
                            message: "runtime_ui_error",
                            data: [
                                "providerId": provider.id,
                                "messageLen": "\(message.count)",
                                "renderedLen": "\(textSnapshot.count)",
                            ]
                        )
                        // #endregion
                        await MainActor.run { onError(textSnapshot + "\n\n[Error: \(message)]") }
                        await setState(.error)
                        throw StreamExecutionError.providerError(message)
                    case .completed:
                        await flushCoalescedAssistantText(reason: "completed_event")
                        if !bufferedRawEvents.isEmpty {
                            let pending = bufferedRawEvents
                            bufferedRawEvents.removeAll(keepingCapacity: true)
                            await forwardRawEventsOnMainActor(pending)
                        }
                        // #region agent log
                        RuntimeEvidenceDebugLog.append(
                            hypothesisId: "H8",
                            location: "ConversationFlowCoordinator.runRustTransportStream",
                            message: "runtime_ui_completed",
                            data: [
                                "providerId": provider.id,
                                "renderedLen": "\(renderedTextSnapshot.count)",
                                "turnPrimaryLen": "\(turnState.primaryTextSnapshot.count)",
                            ]
                        )
                        // #endregion
                        await setState(.completed)
                        return renderedTextSnapshot.isEmpty ? turnState.primaryTextSnapshot : renderedTextSnapshot
                    }
                }
                if pollTextDeltaCount > 0 || pollTextReplaceCount > 0 {
                    // #region agent log
                    RuntimeEvidenceDebugLog.append(
                        hypothesisId: "H23",
                        location: "ConversationFlowCoordinator.runRustTransportStream",
                        message: "runtime_poll_text_batch",
                        data: [
                            "providerId": provider.id,
                            "uiEventCount": "\(response.uiEvents.count)",
                            "textDeltaCount": "\(pollTextDeltaCount)",
                            "textReplaceCount": "\(pollTextReplaceCount)",
                            "rawCount": "\(pollRawCount)",
                            "hasSeenNarrativeEvent": "\(hasSeenNarrativeEvent)",
                        ]
                    )
                    // #endregion
                }
                if provider.id == "codex-cli", pollTextDeltaCount > 1, coalescedAssistantTextDirty {
                    // #region agent log
                    RuntimeEvidenceDebugLog.append(
                        hypothesisId: "H39",
                        location: "ConversationFlowCoordinator.runRustTransportStream",
                        message: "codex_text_delta_batch_deferred_to_poll_end",
                        data: [
                            "pollTextDeltaCount": "\(pollTextDeltaCount)",
                            "coalescedAssistantDeltaCount": "\(coalescedAssistantDeltaCount)",
                            "renderedLen": "\(renderedTextSnapshot.count)",
                            "rawCount": "\(pollRawCount)",
                        ]
                    )
                    // #endregion
                }
                await flushCoalescedAssistantText(reason: "poll_end")
                let pollCycleCompletedAt = Date()
                // #region agent log
                RuntimeEvidenceDebugLog.append(
                    hypothesisId: "H27",
                    location: "ConversationFlowCoordinator.runRustTransportStream",
                    message: "runtime_poll_cycle_processed",
                    data: [
                        "providerId": provider.id,
                        "timeoutMs": "\(timeoutMs)",
                        "uiEventCount": "\(response.uiEvents.count)",
                        "signalCount": "\(response.signals.count)",
                        "isTerminal": "\(response.isTerminal)",
                        "didTimeout": "\(response.didTimeout)",
                        "textDeltaCount": "\(pollTextDeltaCount)",
                        "textReplaceCount": "\(pollTextReplaceCount)",
                        "rawCount": "\(pollRawCount)",
                        "pollCallMs": "\(Int(pollReturnedAt.timeIntervalSince(pollCycleStartedAt) * 1000))",
                        "processingMs": "\(Int(pollCycleCompletedAt.timeIntervalSince(pollReturnedAt) * 1000))",
                        "cycleTotalMs": "\(Int(pollCycleCompletedAt.timeIntervalSince(pollCycleStartedAt) * 1000))",
                        "msSincePreviousCycleCompleted": "\(msSincePreviousCycleCompleted)",
                        "textFlushCount": "\(currentPollTextFlushCount)",
                        "textFlushMainActorTotalMs": "\(currentPollTextFlushMainActorTotalMs)",
                        "textFlushMainActorMaxMs": "\(currentPollTextFlushMainActorMaxMs)",
                    ]
                )
                // #endregion
                lastPollCycleCompletedAt = pollCycleCompletedAt

                await Task.yield()
            }
        } onCancel: {
            provider.cancelRuntimeSession(sessionId: sessionId)
        }
    }

    private static func runtimeEventKind(_ event: StreamEvent) -> String {
        switch event {
        case .textDelta, .textReplace:
            return event.isReplace ? "textReplace" : "textDelta"
        case .started:
            return "started"
        case .completed:
            return "completed"
        case .error:
            return "error"
        case .raw:
            return "raw"
        }
    }

    private static func runtimePayload(_ event: StreamEvent) -> [String: String] {
        switch event {
        case .textDelta(let delta):
            return ["delta": delta, "stream_id": "main"]
        case .textReplace(let replacement):
            return ["replacement": replacement, "stream_id": "main"]
        case .raw(_, let payload):
            return payload
        case .error(let message):
            return ["error": message]
        case .started, .completed:
            return [:]
        }
    }
}

private extension MainChatRuntimeSnapshotBridge {
    var currentPollTimeoutSeconds: Int? {
        guard let directStream else { return nil }
        return directStream.hasReceivedAnyEvent ? directStream.activityTimeoutSec : directStream.firstEventTimeoutSec
    }
}

private extension StreamEvent {
    var isReplace: Bool {
        if case .textReplace = self {
            return true
        }
        return false
    }
}
