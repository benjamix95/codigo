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
            var bufferedRawEvents: [(String, [String: String])] = []
            var renderedTextSnapshot = turnState.primaryTextSnapshot
            var pendingReasoningSnapshot = ""
            var coalescedAssistantTextDirty = false
            var consecutiveEmptyUiPolls = 0
            let suppressReasoningUI = ChatReasoningPresentationPolicy.shouldSuppressReasoningUI(
                messageProviderId: nil,
                fallbackTurnProviderId: provider.id
            )
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
            func flushCoalescedAssistantText() async {
                guard coalescedAssistantTextDirty else { return }
                coalescedAssistantTextDirty = false
                let textCopy = renderedTextSnapshot
                await MainActor.run {
                    RuntimeStreamSignpost.measureMainActorTextFlush {
                        onText(textCopy)
                    }
                }
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
                } else {
                    consecutiveEmptyUiPolls = 0
                }
                let eventTimestamp = Date()

                for signal in response.signals {
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
                        }
                    case .textReplace:
                        let isClaudeCliReplace = provider.id == "claude-cli"
                        if !hasSeenNarrativeEvent && isClaudeCliReplace {
                            pendingReasoningSnapshot = event.text
                            await flushClaudeCliReasoningDelta(force: true)
                        } else {
                            hasSeenNarrativeEvent = true
                            renderedTextSnapshot = event.text
                            coalescedAssistantTextDirty = true
                        }
                        await flushCoalescedAssistantText()
                        if !bufferedRawEvents.isEmpty {
                            let pending = bufferedRawEvents
                            bufferedRawEvents.removeAll(keepingCapacity: true)
                            await forwardRawEventsOnMainActor(pending)
                        }
                    case .raw:
                        await flushCoalescedAssistantText()
                        let rawType = event.rawType ?? "provider_raw"
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
                            && shouldBufferOperationalRawEventUntilNarrative(rawType: rawType, payload: event.payload)
                        {
                            bufferedRawEvents.append((rawType, event.payload))
                        } else {
                            if rawType == "reasoning", runtimeStreamLogger.isEnabled(type: .debug) {
                                runtimeStreamLogger.debug("forwarding reasoning to onRaw")
                            }
                            var batch: [(String, [String: String])] = [(rawType, event.payload)]
                            if hasSeenNarrativeEvent, !bufferedRawEvents.isEmpty {
                                batch.append(contentsOf: bufferedRawEvents)
                                bufferedRawEvents.removeAll(keepingCapacity: true)
                            }
                            await forwardRawEventsOnMainActor(batch)
                        }
                    case .error:
                        await flushCoalescedAssistantText()
                        let message = event.text.isEmpty
                            ? (runtimeSnapshot.output?.terminalError ?? "Provider stream failed")
                            : event.text
                        let textSnapshot = renderedTextSnapshot.isEmpty ? turnState.primaryTextSnapshot : renderedTextSnapshot
                        if !bufferedRawEvents.isEmpty {
                            let pending = bufferedRawEvents
                            bufferedRawEvents.removeAll(keepingCapacity: true)
                            await forwardRawEventsOnMainActor(pending)
                        }
                        await MainActor.run { onError(textSnapshot + "\n\n[Error: \(message)]") }
                        await setState(.error)
                        throw StreamExecutionError.providerError(message)
                    case .completed:
                        await flushCoalescedAssistantText()
                        if !bufferedRawEvents.isEmpty {
                            let pending = bufferedRawEvents
                            bufferedRawEvents.removeAll(keepingCapacity: true)
                            await forwardRawEventsOnMainActor(pending)
                        }
                        await setState(.completed)
                        return renderedTextSnapshot.isEmpty ? turnState.primaryTextSnapshot : renderedTextSnapshot
                    }
                }
                await flushCoalescedAssistantText()

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
