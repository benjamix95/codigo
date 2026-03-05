import Foundation

private struct SubagentTimeoutError: LocalizedError {
    var errorDescription: String? { "Subagent execution timed out after 5 minutes" }
}

private actor SubagentExecutionLimiter {
    static let shared = SubagentExecutionLimiter(maxConcurrent: 4)

    private let maxConcurrent: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func acquire() async {
        if running < maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        // Waiter resumed by release() — count the slot for this waiter.
        // release() already kept `running` unchanged (didn't decrement) when
        // resuming a waiter, so the slot is implicitly transferred. We still
        // need to increment because release() didn't touch the counter.
        running += 1
    }

    func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            // Transfer the slot: decrement for the releaser, the resumed waiter
            // will increment in acquire() after resumption.
            running -= 1
            next.resume()
            return
        }
        running = max(0, running - 1)
    }

    func withPermit<T>(_ operation: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }
}

extension ToolEnabledLLMProvider {
    /// The subagent runs to completion using its own ToolEnabledLLMProvider instance,
    /// then returns the result as tool output events.
    /// When `preAssignedSubagentId` is provided, the "started" event was already emitted
    /// by the caller and will not be duplicated here.
    /// `onLiveEvent` is called for every intermediate event during execution, enabling
    /// real-time streaming of subagent activity to the UI (card subtitle updates, etc.).
    func executeSubagentTool(
        toolName: String,
        marker: CoderIDEMarker,
        context: WorkspaceContext,
        preAssignedSubagentId: String? = nil,
        onLiveEvent: (@Sendable (StreamEvent) -> Void)? = nil
    ) async -> [StreamEvent] {
        guard let role = SubagentRole.fromToolName(toolName) else {
            return [.raw(type: "tool_validation_error", payload: [
                "id": marker.payload["id"] ?? UUID().uuidString,
                "name": toolName,
                "title": "Unknown subagent",
                "detail": "No subagent role for '\(toolName)'",
                "status": "failed",
                "error_code": "unknown_subagent"
            ])]
        }

        let task = marker.payload["task"] ?? marker.payload["prompt"] ?? ""
        guard !task.isEmpty else {
            return [.raw(type: "tool_validation_error", payload: [
                "id": marker.payload["id"] ?? UUID().uuidString,
                "name": toolName,
                "title": "Missing task",
                "detail": "subagent_* tools require a 'task' argument describing what the subagent should do.",
                "status": "failed",
                "error_code": "missing_argument"
            ])]
        }

        return await SubagentExecutionLimiter.shared.withPermit {
            await executeSubagentToolWithAcquiredSlot(
                toolName: toolName,
                role: role,
                task: task,
                marker: marker,
                context: context,
                preAssignedSubagentId: preAssignedSubagentId,
                onLiveEvent: onLiveEvent
            )
        }
    }

    private func executeSubagentToolWithAcquiredSlot(
        toolName: String,
        role: SubagentRole,
        task: String,
        marker: CoderIDEMarker,
        context: WorkspaceContext,
        preAssignedSubagentId: String?,
        onLiveEvent: (@Sendable (StreamEvent) -> Void)?
    ) async -> [StreamEvent] {
        let subagentId = preAssignedSubagentId ?? "\(role.rawValue)-\(UUID().uuidString.prefix(8))"
        let toolCallId = marker.payload["id"] ?? UUID().uuidString
        var events: [StreamEvent] = []

        // Only emit "started" if it wasn't already emitted by the caller
        // (parallel batch pre-emits started events for immediate UI feedback).
        if preAssignedSubagentId == nil {
            events.append(.raw(type: "agent", payload: [
                "title": role.displayName,
                "detail": "started",
                "swarm_id": subagentId,
                "group_id": "swarm-\(subagentId)",
                "tool_call_id": toolCallId,
                "status": "started"
            ]))
        }

        let startDate = Date()

        do {
            // Create the subagent's LLM provider
            let subagentBase = subagentProviderFactory?() ?? base

            // Build runtime: for explorer, restrict to read-only policy
            let subagentRuntime = UnifiedToolRuntime(
                executionController: nil,
                executionScope: .swarm
            )

            let subagentPolicy: ToolRuntimePolicy = role.canEditFiles ? policy : ToolRuntimePolicy(
                sandboxMode: "workspace-read",
                askForApproval: policy.askForApproval,
                timeoutMs: policy.timeoutMs,
                maxToolCallsPerRound: policy.maxToolCallsPerRound,
                maxRepeatedSameToolPerRound: policy.maxRepeatedSameToolPerRound,
                maxBashOutputBytes: policy.maxBashOutputBytes,
                maxReadBytesPerFile: policy.maxReadBytesPerFile,
                allowDangerousShellPatterns: false,
                allowMutatingTools: false,
                enableMCP: policy.enableMCP,
                enforceMCPEditOnly: policy.enforceMCPEditOnly,
                mcpPerCallTimeoutMs: policy.mcpPerCallTimeoutMs,
                mcpSessionIdleTTLSeconds: policy.mcpSessionIdleTTLSeconds
            )
            let subagentProvider = ToolEnabledLLMProvider(
                base: subagentBase,
                runtime: subagentRuntime,
                policy: subagentPolicy,
                executionScope: .swarm,
                maxToolRounds: role.maxToolRounds,
                subagentProviderFactory: nil  // no nested subagents
            )

            // Build the subagent prompt
            let prompt = SubagentPromptBuilder.build(role: role, task: task)

            // Run the subagent to completion
            var fullTextParts: [String] = []
            var fullTextLength = 0
            var liveTextBuffer = ""
            var lastLiveEmitAt = Date.distantPast
            let hasLiveCallback = onLiveEvent != nil

            func emitBufferedLiveTextIfNeeded(force: Bool = false) {
                guard hasLiveCallback else { return }
                guard !liveTextBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    liveTextBuffer = ""
                    return
                }
                let now = Date()
                let shouldEmit =
                    force
                    || liveTextBuffer.count >= 1200
                    || now.timeIntervalSince(lastLiveEmitAt) >= 0.20
                guard shouldEmit else { return }
                onLiveEvent?(.raw(type: "subagent_text", payload: [
                    "swarm_id": subagentId,
                    "group_id": "swarm-\(subagentId)",
                    "text": String(liveTextBuffer.prefix(1200)),
                    "_live_emitted": "1"
                ]))
                liveTextBuffer = ""
                lastLiveEmitAt = now
            }

            // Wrap both stream creation AND iteration inside the task group
            // so the 5-minute timeout covers the full subagent execution,
            // not just the instant stream-creation call.
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    let stream = try await subagentProvider.send(
                        prompt: prompt, context: context, imageURLs: nil
                    )
                    for try await event in stream {
                        try Task.checkCancellation()
                        switch event {
                        case .textDelta(let delta):
                            if fullTextLength + delta.count <= 50_000 { fullTextParts.append(delta); fullTextLength += delta.count }
                            if hasLiveCallback, !delta.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                                liveTextBuffer += delta
                                if liveTextBuffer.count > 2400 {
                                    liveTextBuffer = String(liveTextBuffer.suffix(2400))
                                }
                                emitBufferedLiveTextIfNeeded()
                            }
                        case .raw(let type, var payload):
                            emitBufferedLiveTextIfNeeded(force: true)
                            payload["swarm_id"] = subagentId
                            payload["group_id"] = "swarm-\(subagentId)"
                            if hasLiveCallback {
                                payload["_live_emitted"] = "1"
                            }
                            let enriched = StreamEvent.raw(type: type, payload: payload)
                            events.append(enriched)
                            onLiveEvent?(enriched)
                        default:
                            break
                        }
                    }
                    emitBufferedLiveTextIfNeeded(force: true)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
                    throw SubagentTimeoutError()
                }
                // First task to finish (or throw) wins; cancel the other.
                try await group.next()
                group.cancelAll()
            }

            let durationMs = Int(Date().timeIntervalSince(startDate) * 1000)
            let output = String(fullTextParts.joined().prefix(Self.subagentOutputLimit(for: role)))

            // Emit completed event
            events.append(.raw(type: "agent", payload: [
                "title": role.displayName,
                "detail": "completed",
                "swarm_id": subagentId,
                "group_id": "swarm-\(subagentId)",
                "tool_call_id": toolCallId,
                "status": "completed",
                "duration_ms": "\(durationMs)"
            ]))

            // Return result as a tool result event so the main agent gets the output
            events.append(.raw(type: "tool_result", payload: [
                "id": toolCallId,
                "name": toolName,
                "title": "\(role.displayName) completed",
                "detail": "\(role.displayName) subagent completed in \(durationMs)ms",
                "output": output,
                "status": "completed",
                "subagent_id": subagentId,
                "role": role.rawValue,
                "duration_ms": "\(durationMs)"
            ]))

        } catch {
            let durationMs = Int(Date().timeIntervalSince(startDate) * 1000)

            events.append(.raw(type: "agent", payload: [
                "title": role.displayName,
                "detail": "failed",
                "swarm_id": subagentId,
                "group_id": "swarm-\(subagentId)",
                "tool_call_id": toolCallId,
                "status": "failed"
            ]))

            events.append(.raw(type: "tool_result", payload: [
                "id": toolCallId,
                "name": toolName,
                "title": "\(role.displayName) failed",
                "detail": error.localizedDescription,
                "output": "Subagent \(role.displayName) failed: \(error.localizedDescription)",
                "status": "failed",
                "subagent_id": subagentId,
                "duration_ms": "\(durationMs)"
            ]))
        }

        return events
    }

    // MARK: - Skill Execution

}

private extension ToolEnabledLLMProvider {
    static func subagentOutputLimit(for role: SubagentRole) -> Int {
        switch role {
        case .reviewer, .securityAuditor:
            return 20_000
        default:
            return 8_000
        }
    }
}
