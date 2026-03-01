import Foundation

/// Lightweight internal representation of a tool call used by the tool execution loop.
/// Previously part of CoderIDEMarkerParser; kept here for the native tool_call_suggested path.
struct CoderIDEMarker {
    let kind: String
    let payload: [String: String]
}

public final class ToolEnabledLLMProvider: LLMProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public var attachmentCapabilities: ProviderAttachmentCapabilities {
        base.attachmentCapabilities
    }

    private let base: any LLMProvider
    private let runtime: UnifiedToolRuntime
    private let policy: ToolRuntimePolicy
    private let executionScope: ExecutionScope
    private let maxToolRounds: Int
    private let maxAutonomousContinuationRounds = 4

    /// Optional factory for creating base LLM providers for subagent execution.
    /// If nil, subagents reuse the same base provider as the parent agent.
    private let subagentProviderFactory: (@Sendable () -> any LLMProvider)?

    public init(
        base: any LLMProvider,
        runtime: UnifiedToolRuntime? = nil,
        policy: ToolRuntimePolicy = ToolRuntimePolicy(),
        executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        maxToolRounds: Int = 160,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) {
        self.base = base
        self.id = base.id
        self.displayName = base.displayName
        self.runtime = runtime ?? UnifiedToolRuntime(executionController: executionController, executionScope: executionScope)
        self.policy = policy
        self.executionScope = executionScope
        self.maxToolRounds = max(1, maxToolRounds)
        self.subagentProviderFactory = subagentProviderFactory
    }

    public func isAuthenticated() -> Bool {
        base.isAuthenticated()
    }

    public func debugToolRuntimeSnapshot() async -> ToolRuntimeDebugSnapshot {
        await runtime.debugSnapshot()
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        // When systemPromptOverride is set (e.g. prompt optimization), pass through to base without
        // adding taskCompletionStrict or toolProtocolPrompt — the context carries the custom system prompt.
        if context.systemPromptOverride != nil {
            return try await base.send(prompt: prompt, context: context, imageURLs: imageURLs)
        }

        // Eagerly discover and register MCP tools as native function tools on first request.
        if policy.enableMCP && !MCPNativeToolRegistry.shared.hasTools() {
            let discovered = await runtime.mcpSessions.discoverAllTools(
                idleTTLSeconds: policy.mcpSessionIdleTTLSeconds
            )
            if !discovered.isEmpty {
                MCPNativeToolRegistry.shared.register(tools: discovered)
            }
        }

        let initialPrompt = """
        \(SystemPrompts.taskCompletionStrict)

        \(toolProtocolPrompt)

        \(prompt)
        """

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var currentPrompt = initialPrompt
                    var conversationTranscript = ""
                    var isFirstRound = true
                    var extraContinuationRounds = 0
                    var lastToolResultsForFallback: [[String: String]] = []
                    var emittedVisibleTextAfterToolRound = false
                    var hasAnyMeaningfulAssistantText = false
                    let requiredPolicyHash = Self.requiredPolicyHash(from: context)
                    var didEmitPolicyAck = false
                    let enforceSubagentFirstRound = executionScope == .agent && subagentProviderFactory != nil
                    var acceptedSubagentInFirstRound = false
                    var sawCodeMutationDuringTask = false
                    var reviewerCompletedAfterLatestMutation = false
                    var testWriterCompletedAfterLatestMutation = false
                    var autoInjectedFinalReviewBatchCount = 0
                    let maxAutoInjectedFinalReviewBatchCount = 4

                    for _ in 0..<maxToolRounds {
                        let stream = try await base.send(prompt: currentPrompt, context: context, imageURLs: isFirstRound ? imageURLs : nil)
                        var roundText = ""
                        var roundToolResults: [[String: String]] = []
                        // Dedupe only for the current round: subsequent rounds can
                        // legitimately re-emit the same tool/id.
                        var emittedMarkerIds = Set<String>()
                        var toolCallCountByKey: [String: Int] = [:]
                        var toolCallsThisRound = 0
                        var sawExecutableSuggestion = false
                        // Subagent calls are deferred and executed in parallel after the stream ends.
                        var pendingSubagentCalls: [(marker: CoderIDEMarker, name: String)] = []
                        // Use array to avoid O(n²) string concatenation
                        var roundTextParts: [String] = []
                        var roundTextLength = 0

                        for try await event in stream {
                            switch event {
                            case .textDelta(let delta):
                                let visibleDelta = sanitizeVisibleDelta(delta)
                                if !visibleDelta.isEmpty, roundTextLength + visibleDelta.count <= 100_000 { roundTextParts.append(visibleDelta); roundTextLength += visibleDelta.count }
                                if !visibleDelta.isEmpty {
                                    continuation.yield(.textDelta(visibleDelta))
                                    if isMeaningfulAssistantCompletion(visibleDelta) {
                                        emittedVisibleTextAfterToolRound = true
                                        hasAnyMeaningfulAssistantText = true
                                    }
                                }
                            case .started:
                                if isFirstRound {
                                    continuation.yield(.started)
                                }
                            case .completed:
                                break
                            case .raw(let type, let payload):
                                if type == "policy_ack" {
                                    if Self.matchesRequiredPolicyHash(
                                        payload["hash"] ?? payload["policy_hash"],
                                        requiredHash: requiredPolicyHash
                                    ) {
                                        didEmitPolicyAck = true
                                    }
                                    continuation.yield(event)
                                    continue
                                }
                                if let hash = requiredPolicyHash,
                                   shouldEmitSyntheticPolicyAck(
                                    forRawEventType: type,
                                    requiredHash: hash,
                                    didEmitPolicyAck: didEmitPolicyAck
                                   ) {
                                    continuation.yield(.raw(type: "policy_ack", payload: ["hash": hash]))
                                    didEmitPolicyAck = true
                                }
                                if type == "tool_call_suggested" {
                                    let isPartial = (payload["is_partial"] ?? "").lowercased() == "true"
                                    if isPartial { continue }
                                    let name = inferredToolName(from: payload)
                                    if name.isEmpty { continue }
                                    if toolCallsThisRound >= policy.maxToolCallsPerRound {
                                        continuation.yield(.raw(type: "tool_execution_error", payload: [
                                            "title": "Tool budget exceeded",
                                            "detail": "Reached tool limit per round (\(policy.maxToolCallsPerRound))",
                                            "status": "failed",
                                            "error_code": "budget_exceeded"
                                        ]))
                                        continue
                                    }
                                    var args = payload
                                    let metadataKeys: Set<String> = [
                                        "id", "name", "tool", "tool_name", "function", "function_name",
                                        "args", "is_partial", "type", "status", "title", "detail", "output",
                                    ]
                                    for key in metadataKeys {
                                        args.removeValue(forKey: key)
                                    }
                                    if let argsJson = payload["args"], let parsed = parseArgsJSON(argsJson) {
                                        for (key, value) in parsed {
                                            args[key] = value
                                        }
                                    }
                                    args["id"] = payload["id"] ?? args["id"] ?? UUID().uuidString
                                    args["name"] = name
                                    let marker = CoderIDEMarker(kind: "tool_call", payload: args)
                                    let legacyInvokeSwarm = Self.isLegacyInvokeSwarmSuggestion(
                                        toolName: name,
                                        payload: args
                                    )

                                    if enforceSubagentFirstRound,
                                       isFirstRound,
                                       !acceptedSubagentInFirstRound,
                                       !name.hasPrefix("subagent_"),
                                       !legacyInvokeSwarm,
                                       !Self.isSubagentFirstRoundExemptTool(name)
                                    {
                                        continuation.yield(.raw(type: "tool_validation_error", payload: [
                                            "title": "Subagent-first policy",
                                            "detail": "First operational tool round must start with subagent_* delegation before direct tool execution.",
                                            "status": "failed",
                                            "error_code": "subagent_first_required",
                                            "tool": name,
                                        ]))
                                        sawExecutableSuggestion = true
                                        continue
                                    }

                                    let dedupeId = markerDedupeKey(marker)
                                    let count = toolCallCountByKey[dedupeId, default: 0]
                                    if count >= policy.maxRepeatedSameToolPerRound { continue }
                                    toolCallCountByKey[dedupeId] = count + 1
                                    emittedMarkerIds.insert(dedupeId)
                                    toolCallsThisRound += 1
                                    sawExecutableSuggestion = true
                                    if isFirstRound, legacyInvokeSwarm {
                                        acceptedSubagentInFirstRound = true
                                    }
                                    if let hash = requiredPolicyHash,
                                       shouldEmitSyntheticPolicyAck(
                                        for: marker,
                                        requiredHash: hash,
                                        didEmitPolicyAck: didEmitPolicyAck
                                       ) {
                                        continuation.yield(.raw(type: "policy_ack", payload: ["hash": hash]))
                                        didEmitPolicyAck = true
                                    }
                                    // Subagent tools are deferred for parallel execution
                                    // after the current stream round ends.
                                    if name.hasPrefix("subagent_") {
                                        if isFirstRound {
                                            acceptedSubagentInFirstRound = true
                                        }
                                        pendingSubagentCalls.append((marker: marker, name: name))
                                        let toolCallId = marker.payload["id"] ?? UUID().uuidString
                                        continuation.yield(.raw(type: "agent", payload: [
                                            "title": SubagentRole.fromToolName(name)?.displayName ?? name,
                                            "detail": "queued",
                                            "swarm_id": "queued-\(toolCallId)",
                                            "tool_call_id": toolCallId,
                                            "status": "queued"
                                        ]))
                                    } else {
                                        // Emit a real-time "started" event BEFORE tool execution
                                        // so the tool trace shows live progress (like Codex CLI).
                                        // Todo updates are lightweight state events and should not
                                        // be represented as generic running tool operations.
                                        if name != "todo_write", name != "todo_read" {
                                            let startType = Self.toolStartEventType(for: name)
                                            let startPayload = Self.toolStartPayload(for: name, args: args)
                                            continuation.yield(.raw(type: startType, payload: startPayload))
                                        }

                                        let produced = await events(for: marker, context: context)
                                        for e in produced {
                                            if Self.streamEventIndicatesCodeMutation(
                                                e,
                                                originatingToolName: name
                                            ) {
                                                sawCodeMutationDuringTask = true
                                                reviewerCompletedAfterLatestMutation = false
                                                testWriterCompletedAfterLatestMutation = false
                                            }
                                            if let completedRole = Self.completedSubagentRole(from: e) {
                                                if completedRole == .reviewer {
                                                    reviewerCompletedAfterLatestMutation = true
                                                }
                                                if completedRole == .testWriter {
                                                    testWriterCompletedAfterLatestMutation = true
                                                }
                                            }
                                            if case .raw(let innerType, let innerPayload) = e,
                                               innerType == "policy_ack",
                                               Self.matchesRequiredPolicyHash(
                                                innerPayload["hash"] ?? innerPayload["policy_hash"],
                                                requiredHash: requiredPolicyHash
                                               ) {
                                                didEmitPolicyAck = true
                                            }
                                            continuation.yield(e)
                                        }
                                        if let summary = summarizeToolResultEvents(produced, marker: marker) {
                                            roundToolResults.append(summary)
                                        }
                                    }
                                } else {
                                    continuation.yield(event)
                                }
                            default:
                                continuation.yield(event)
                            }
                        }

                        // Execute deferred subagent calls in parallel via withTaskGroup.
                        if !pendingSubagentCalls.isEmpty {
                            let calls = pendingSubagentCalls
                            let capturedContext = context
                            let results: [(events: [StreamEvent], marker: CoderIDEMarker)] = await withTaskGroup(
                                of: (events: [StreamEvent], marker: CoderIDEMarker).self
                            ) { group in
                                for call in calls {
                                    let m = call.marker
                                    group.addTask {
                                        let produced = await self.events(for: m, context: capturedContext)
                                        return (events: produced, marker: m)
                                    }
                                }
                                var collected: [(events: [StreamEvent], marker: CoderIDEMarker)] = []
                                for await result in group {
                                    collected.append(result)
                                }
                                return collected
                            }
                            // Emit results sequentially after parallel execution
                            var anySubagentFailed = false
                            for result in results {
                                let subagentToolName = result.marker.payload["name"] ?? result.marker.payload["tool"] ?? ""
                                for e in result.events {
                                    if Self.streamEventIndicatesCodeMutation(
                                        e,
                                        originatingToolName: subagentToolName
                                    ) {
                                        sawCodeMutationDuringTask = true
                                        reviewerCompletedAfterLatestMutation = false
                                        testWriterCompletedAfterLatestMutation = false
                                    }
                                    if let completedRole = Self.completedSubagentRole(from: e) {
                                        if completedRole == .reviewer {
                                            reviewerCompletedAfterLatestMutation = true
                                        }
                                        if completedRole == .testWriter {
                                            testWriterCompletedAfterLatestMutation = true
                                        }
                                    }
                                    if case .raw(let innerType, let innerPayload) = e,
                                       innerType == "policy_ack",
                                       Self.matchesRequiredPolicyHash(
                                        innerPayload["hash"] ?? innerPayload["policy_hash"],
                                        requiredHash: requiredPolicyHash
                                       ) {
                                        didEmitPolicyAck = true
                                    }
                                    if case .raw(let t, let p) = e,
                                       t == "tool_result",
                                       p["status"] == "failed" {
                                        anySubagentFailed = true
                                    }
                                    continuation.yield(e)
                                }
                                if let summary = summarizeToolResultEvents(result.events, marker: result.marker) {
                                    roundToolResults.append(summary)
                                }
                            }
                            // Auto-complete in-progress todos after subagent batch finishes.
                            // The agent will continue in the next round and can update further.
                            let autoStatus = anySubagentFailed ? "blocked" : "done"
                            continuation.yield(.raw(type: "subagent_batch_done", payload: [
                                "status": autoStatus,
                                "count": "\(results.count)"
                            ]))
                            pendingSubagentCalls.removeAll()
                        }

                        let mandatoryReviewSatisfied =
                            reviewerCompletedAfterLatestMutation && testWriterCompletedAfterLatestMutation
                        if subagentProviderFactory != nil,
                           sawCodeMutationDuringTask,
                           !mandatoryReviewSatisfied,
                           autoInjectedFinalReviewBatchCount < maxAutoInjectedFinalReviewBatchCount
                        {
                            autoInjectedFinalReviewBatchCount += 1
                            var injectedCalls: [(marker: CoderIDEMarker, name: String)] = []
                            if !reviewerCompletedAfterLatestMutation {
                                injectedCalls.append((
                                    marker: CoderIDEMarker(kind: "tool_call", payload: [
                                        "id": "auto-reviewer-\(UUID().uuidString)",
                                        "name": SubagentRole.reviewer.toolName,
                                        "task": "Review all code changes completed in this task. Report bugs, regressions, and risks with concrete findings.",
                                    ]),
                                    name: SubagentRole.reviewer.toolName
                                ))
                            }
                            if !testWriterCompletedAfterLatestMutation {
                                injectedCalls.append((
                                    marker: CoderIDEMarker(kind: "tool_call", payload: [
                                        "id": "auto-testwriter-\(UUID().uuidString)",
                                        "name": SubagentRole.testWriter.toolName,
                                        "task": "Write and run focused regression tests for all code changes completed in this task. Report failures and coverage gaps.",
                                    ]),
                                    name: SubagentRole.testWriter.toolName
                                ))
                            }

                            if !injectedCalls.isEmpty {
                                sawExecutableSuggestion = true
                                for call in injectedCalls {
                                    let toolCallId = call.marker.payload["id"] ?? UUID().uuidString
                                    continuation.yield(.raw(type: "agent", payload: [
                                        "title": SubagentRole.fromToolName(call.name)?.displayName ?? call.name,
                                        "detail": "queued",
                                        "swarm_id": "queued-\(toolCallId)",
                                        "tool_call_id": toolCallId,
                                        "status": "queued"
                                    ]))
                                }

                                let capturedContext = context
                                let injectedResults: [(events: [StreamEvent], marker: CoderIDEMarker)] = await withTaskGroup(
                                    of: (events: [StreamEvent], marker: CoderIDEMarker).self
                                ) { group in
                                    for call in injectedCalls {
                                        let marker = call.marker
                                        group.addTask {
                                            let produced = await self.events(for: marker, context: capturedContext)
                                            return (events: produced, marker: marker)
                                        }
                                    }
                                    var collected: [(events: [StreamEvent], marker: CoderIDEMarker)] = []
                                    for await result in group {
                                        collected.append(result)
                                    }
                                    return collected
                                }

                                var injectedAnyFailed = false
                                for result in injectedResults {
                                    let subagentToolName = result.marker.payload["name"] ?? result.marker.payload["tool"] ?? ""
                                    for e in result.events {
                                        if Self.streamEventIndicatesCodeMutation(
                                            e,
                                            originatingToolName: subagentToolName
                                        ) {
                                            sawCodeMutationDuringTask = true
                                            reviewerCompletedAfterLatestMutation = false
                                            testWriterCompletedAfterLatestMutation = false
                                        }
                                        if let completedRole = Self.completedSubagentRole(from: e) {
                                            if completedRole == .reviewer {
                                                reviewerCompletedAfterLatestMutation = true
                                            }
                                            if completedRole == .testWriter {
                                                testWriterCompletedAfterLatestMutation = true
                                            }
                                        }
                                        if case .raw(let innerType, let innerPayload) = e,
                                           innerType == "policy_ack",
                                           Self.matchesRequiredPolicyHash(
                                            innerPayload["hash"] ?? innerPayload["policy_hash"],
                                            requiredHash: requiredPolicyHash
                                           ) {
                                            didEmitPolicyAck = true
                                        }
                                        if case .raw(let t, let p) = e,
                                           t == "tool_result",
                                           p["status"] == "failed" {
                                            injectedAnyFailed = true
                                        }
                                        continuation.yield(e)
                                    }
                                    if let summary = summarizeToolResultEvents(result.events, marker: result.marker) {
                                        roundToolResults.append(summary)
                                    }
                                }

                                continuation.yield(.raw(type: "subagent_batch_done", payload: [
                                    "status": injectedAnyFailed ? "blocked" : "done",
                                    "count": "\(injectedResults.count)"
                                ]))
                            }
                        }

                        roundText = roundTextParts.joined()
                        conversationTranscript += "\n[assistant]\n\(roundText)\n"
                        // Cap transcript to avoid exponential prompt growth
                        if conversationTranscript.count > 48_000 {
                            conversationTranscript = String(conversationTranscript.suffix(40_000))
                        }
                        if !roundToolResults.isEmpty {
                            lastToolResultsForFallback = roundToolResults
                            emittedVisibleTextAfterToolRound = false
                        }
                        var shouldContinue = !roundToolResults.isEmpty || sawExecutableSuggestion
                        if !shouldContinue,
                           shouldForceAutonomousContinuation(
                            roundText,
                            roundIndex: extraContinuationRounds
                           ),
                           extraContinuationRounds < maxAutonomousContinuationRounds {
                            shouldContinue = true
                            extraContinuationRounds += 1
                        }
                        guard shouldContinue else { break }
                        currentPrompt = buildFollowUpPrompt(
                            originalPrompt: prompt,
                            transcript: conversationTranscript,
                            toolResults: roundToolResults
                        )
                        isFirstRound = false
                    }

                    if !lastToolResultsForFallback.isEmpty && !emittedVisibleTextAfterToolRound {
                        let forcedPrompt = buildForcedFinalizationPrompt(
                            originalPrompt: prompt,
                            transcript: conversationTranscript,
                            toolResults: lastToolResultsForFallback
                        )
                        do {
                            let forcedStream = try await base.send(
                                prompt: forcedPrompt,
                                context: context,
                                imageURLs: nil
                            )
                            var forcedTextParts: [String] = []
                            var forcedTextLength = 0
                            for try await forcedEvent in forcedStream {
                                switch forcedEvent {
                                case .textDelta(let delta):
                                    let visible = sanitizeVisibleDelta(delta)
                                    if !visible.isEmpty {
                                        continuation.yield(.textDelta(visible))
                                        if forcedTextLength + visible.count <= 50_000 { forcedTextParts.append(visible); forcedTextLength += visible.count }
                                    }
                                default:
                                    break
                                }
                            }
                            if !isMeaningfulAssistantCompletion(forcedTextParts.joined()) {
                                continuation.yield(.raw(type: "tool_execution_error", payload: [
                                    "title": "Missing final outcome",
                                    "detail": "Provider finished without final summary after tool execution",
                                    "status": "failed",
                                    "error_code": "missing_final_outcome"
                                ]))
                                let fallback = buildToolFallbackSummary(lastToolResultsForFallback)
                                if !fallback.isEmpty {
                                    continuation.yield(.textDelta(fallback))
                                }
                            } else {
                                hasAnyMeaningfulAssistantText = true
                            }
                        } catch {
                            continuation.yield(.raw(type: "tool_execution_error", payload: [
                                "title": "Finalization failed",
                                "detail": error.localizedDescription,
                                "status": "failed",
                                "error_code": "missing_final_outcome"
                            ]))
                            let fallback = buildToolFallbackSummary(lastToolResultsForFallback)
                            if !fallback.isEmpty {
                                continuation.yield(.textDelta(fallback))
                            }
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                    if !hasAnyMeaningfulAssistantText && !lastToolResultsForFallback.isEmpty {
                        continuation.yield(.raw(type: "tool_execution_error", payload: [
                            "title": "Missing final output",
                            "detail": "No meaningful final content produced",
                            "status": "failed",
                            "error_code": "missing_final_outcome"
                        ]))
                    }
                    if subagentProviderFactory != nil,
                       sawCodeMutationDuringTask,
                       !(reviewerCompletedAfterLatestMutation && testWriterCompletedAfterLatestMutation)
                    {
                        continuation.yield(.raw(type: "tool_validation_error", payload: [
                            "title": "Mandatory review incomplete",
                            "detail": "Code mutations were detected, but reviewer/testWriter coverage for the latest changes is incomplete.",
                            "status": "failed",
                            "error_code": "mandatory_review_incomplete"
                        ]))
                    }

                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func summarizeToolResultEvents(_ events: [StreamEvent], marker: CoderIDEMarker) -> [String: String]? {
        var summary: [String: String] = [
            "id": marker.payload["id"] ?? UUID().uuidString,
            "name": marker.payload["name"] ?? ""
        ]
        var foundCompletion = false
        for event in events {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "tool_execution_error" || payload["status"] == "failed" {
                summary["status"] = "failed"
                summary["detail"] = payload["detail"] ?? payload["stderr"] ?? "tool failed"
                foundCompletion = true
            } else if payload["status"] == "completed" {
                summary["status"] = "completed"
                summary["detail"] = payload["detail"] ?? payload["title"] ?? "ok"
                let name = (summary["name"] ?? "").lowercased()
                if let output = payload["output"], !output.isEmpty, name != "bash" && name != "command_execution" {
                    summary["output"] = String(output.prefix(8000))
                }
                if let path = payload["path"] ?? payload["file"], !path.isEmpty {
                    summary["path"] = path
                }
                foundCompletion = true
            }
        }
        return foundCompletion ? summary : nil
    }

    private func buildFollowUpPrompt(originalPrompt: String, transcript: String, toolResults: [[String: String]]) -> String {
        let resultsSection: String
        if toolResults.isEmpty {
            resultsSection = """
            (No tools used in the previous round.)

            Continue the task autonomously until completion.
            If you need more tools, use tool calls and execute/verify/fix loops as needed.
            Do not stop at a plan or intention statement.
            When finished: you MUST provide a final summary to the user — what changed, which files, outcome, verification.
            """
        } else {
            let formatted = toolResults.map { result in
                let id = result["id"] ?? "-"
                let name = result["name"] ?? "-"
                let status = result["status"] ?? "unknown"
                let detail = result["detail"] ?? ""
                let path = result["path"].map { "\npath: \($0)" } ?? ""
                let nameLower = name.lowercased()
                let output: String
                if nameLower == "bash" || nameLower == "command_execution" {
                    output = ""
                } else {
                    output = result["output"].map { "\noutput:\n\($0)" } ?? ""
                }
                return "- tool_call id=\(id), name=\(name), status=\(status)\n  detail: \(detail)\(path)\(output)"
            }.joined(separator: "\n")
            resultsSection = """
            Tool results from previous round:
            \(formatted)

            Continue using these results autonomously.
            If you need more tools, use tool calls and keep iterating until done.
            If a check fails, fix and re-check before finalizing.
            When finished: you MUST provide a final summary to the user — what changed, which files, outcome, verification.
            """
        }

        return """
        \(toolProtocolPrompt)

        Original user prompt:
        \(originalPrompt)

        Conversation transcript:
        \(String(transcript.suffix(48_000)))

        \(resultsSection)
        """
    }

    private func parseArgsJSON(_ raw: String) -> [String: String]? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else {
            return nil
        }
        var out: [String: String] = [:]
        for (k, v) in dict {
            if let s = v as? String {
                out[k] = s
            } else if v is NSNull {
                out[k] = "null"
            } else if let b = v as? Bool {
                out[k] = b ? "true" : "false"
            } else if let n = v as? NSNumber {
                out[k] = n.stringValue
            } else if JSONSerialization.isValidJSONObject(v) {
                if let jsonData = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys]),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    out[k] = jsonStr
                } else {
                    out[k] = String(describing: v)
                }
            } else {
                out[k] = String(describing: v)
            }
        }
        return out
    }

    private func markerDedupeKey(_ marker: CoderIDEMarker) -> String {
        if marker.kind == "tool_call", let id = marker.payload["id"], !id.isEmpty {
            return "\(marker.kind)|id=\(id)"
        }
        let stablePayload = marker.payload
            .filter { $0.key.lowercased() != "id" }
            .map { key, value in "\(key)=\(value)" }
            .sorted()
            .joined(separator: "|")
        return "\(marker.kind)|\(stablePayload)"
    }

    private func shouldEmitSyntheticPolicyAck(
        for marker: CoderIDEMarker,
        requiredHash: String,
        didEmitPolicyAck: Bool
    ) -> Bool {
        guard !didEmitPolicyAck else { return false }
        guard markerRequiresPolicyAck(marker) else { return false }
        return !requiredHash.isEmpty
    }

    private func markerRequiresPolicyAck(_ marker: CoderIDEMarker) -> Bool {
        switch marker.kind {
        case "policy_ack", "todo_read", "todo_write", "plan_step":
            return false
        case "tool_call":
            let toolName = inferredToolName(from: marker.payload)
            if [
                "todo_read", "todo_write", "plan_step_update", "mermaid_render",
                "debug_set_phase", "debug_request_user", "debug_resolve",
                "policy_ack", "activate_plan_mode", "activate_debug_mode",
                "show_task_panel", "invoke_swarm", "show_swarm_panel",
            ].contains(toolName) {
                return false
            }
            return true
        default:
            return true
        }
    }

    private func shouldEmitSyntheticPolicyAck(
        forRawEventType type: String,
        requiredHash: String,
        didEmitPolicyAck: Bool
    ) -> Bool {
        guard !didEmitPolicyAck, !requiredHash.isEmpty else { return false }
        return rawEventRequiresPolicyAck(type)
    }

    private func rawEventRequiresPolicyAck(_ type: String) -> Bool {
        switch type {
        case "policy_ack", "turn_started", "turn_completed", "usage", "reasoning",
            "todo_read", "todo_write", "plan_step_update", "context_compacted",
            "debug_phase_update", "debug_user_request", "debug_resolved",
            "activate_plan_mode", "activate_debug_mode",
            "coderide_show_task_panel", "coderide_invoke_swarm", "coderide_show_swarm_panel",
            "tool_execution_error", "tool_validation_error", "tool_timeout", "permission_denied":
            return false
        default:
            return true
        }
    }

    private static func isSubagentFirstRoundExemptTool(_ toolName: String) -> Bool {
        switch toolName {
        case "todo_read", "todo_write", "plan_step_update", "mermaid_render",
             "policy_ack", "activate_plan_mode", "activate_debug_mode",
             "show_task_panel", "show_swarm_panel":
            return true
        default:
            return false
        }
    }

    private static func isLegacyInvokeSwarmSuggestion(
        toolName: String,
        payload: [String: String]
    ) -> Bool {
        let normalizedTool = ProviderToolEventMapper.normalizeToolIdentifier(toolName)
        if normalizedTool == "invoke_swarm" {
            return true
        }
        guard normalizedTool == "mcp_call" else {
            return false
        }
        let targetTool = ProviderToolEventMapper.normalizeToolIdentifier(
            payload["tool"] ?? payload["mcp_tool"] ?? payload["tool_name"] ?? ""
        )
        return targetTool == "invoke_swarm"
    }

    private static func isSuccessfulStatus(_ raw: String?) -> Bool {
        let status = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if status.isEmpty { return true }
        return status == "completed" || status == "ok" || status == "success" || status == "done"
    }

    private static func isCodeMutationTool(_ rawTool: String) -> Bool {
        let tool = ProviderToolEventMapper.normalizeToolIdentifier(rawTool)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if tool.isEmpty { return false }
        if tool.hasPrefix("subagent_"),
           let role = SubagentRole.fromToolName(tool) {
            return role == .coder || role == .debugger
        }
        if tool == "create_file" || tool == "delete_file" || tool == "apply_patch" {
            return true
        }
        return tool.contains("edit")
            || tool.contains("write")
            || tool.contains("replace")
            || tool == "parallel_apply"
            || tool == "multi_edit"
            || tool == "find_and_replace_all"
            || tool == "rename_symbol"
            || tool == "undo_edit"
    }

    private static func streamEventIndicatesCodeMutation(
        _ event: StreamEvent,
        originatingToolName: String
    ) -> Bool {
        guard case .raw(let type, let payload) = event else { return false }
        let normalizedType = type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedType == "file_change" {
            return isSuccessfulStatus(payload["status"])
        }
        if normalizedType == "mcp_tool_call" {
            let mcpTool = payload["mcp_tool"] ?? payload["tool"] ?? ""
            return isCodeMutationTool(mcpTool) && isSuccessfulStatus(payload["status"])
        }
        if normalizedType == "tool_result" {
            let tool = payload["name"] ?? originatingToolName
            return isCodeMutationTool(tool) && isSuccessfulStatus(payload["status"])
        }
        return false
    }

    private static func completedSubagentRole(from event: StreamEvent) -> SubagentRole? {
        guard case .raw(let type, let payload) = event else { return nil }
        guard type == "tool_result" else { return nil }
        guard isSuccessfulStatus(payload["status"]) else { return nil }
        let tool = payload["name"] ?? payload["tool"] ?? ""
        return SubagentRole.fromToolName(tool)
    }

    private static func requiredPolicyHash(from context: WorkspaceContext) -> String? {
        let prompt = context.contextPrompt()
        guard !prompt.isEmpty else { return nil }
        // Extract the last policy_ack hash from the context prompt.
        // Matches both marker format [CODERIDE:policy_ack|hash=...] and plain hash= patterns.
        let pattern = #"\bpolicy_ack\b[^]]*\bhash=([^\s|\]\n]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsPrompt = prompt as NSString
        let matches = regex.matches(in: prompt, range: NSRange(location: 0, length: nsPrompt.length))
        // Take the last match (most recent policy hash)
        guard let lastMatch = matches.last, lastMatch.numberOfRanges >= 2 else { return nil }
        let hash = nsPrompt.substring(with: lastMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return hash.isEmpty ? nil : hash
    }

    private static func matchesRequiredPolicyHash(
        _ receivedHash: String?,
        requiredHash: String?
    ) -> Bool {
        guard let requiredHash, !requiredHash.isEmpty else { return true }
        let received = (receivedHash ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !received.isEmpty && received == requiredHash
    }

    /// Resolve a tool call (from native tool_call_suggested) into stream events.
    /// IDE-state tools are emitted as raw events; everything else goes through UnifiedToolRuntime.
    private func events(for marker: CoderIDEMarker, context: WorkspaceContext) async -> [StreamEvent] {
        guard marker.kind == "tool_call" else { return [] }
        let toolName = inferredToolName(from: marker.payload)
        guard !toolName.isEmpty else { return [] }

        if let legacyInvokeEvents = await executeLegacyInvokeSwarmIfNeeded(
            marker: marker,
            toolName: toolName,
            context: context
        ) {
            return legacyInvokeEvents
        }

        if let enforcementEvents = await enforcedMCPEditEventsIfNeeded(
            marker: marker,
            toolName: toolName,
            context: context
        ) {
            return enforcementEvents
        }

        // IDE state tools — pass-through as raw events, not executed through runtime
        switch toolName {
        case "todo_read":
            return [.raw(type: "todo_read", payload: [:])]
        case "todo_write":
            return [.raw(type: "todo_write", payload: marker.payload)]
        case "policy_ack":
            return [.raw(type: "policy_ack", payload: marker.payload)]
        case "plan_step_update":
            return [.raw(type: "plan_step_update", payload: marker.payload)]
        case "debug_panel":
            return [.raw(type: "tool_validation_error", payload: [
                "title": "Legacy debug_panel is not supported",
                "detail": "Use debug_set_phase, debug_request_user, debug_resolve",
                "status": "failed",
                "error_code": "legacy_debug_panel_removed",
                "tool": "debug_panel",
            ])]
        case "debug_set_phase":
            return [.raw(type: "debug_phase_update", payload: marker.payload)]
        case "debug_request_user":
            return [.raw(type: "debug_user_request", payload: marker.payload)]
        case "debug_resolve":
            return [.raw(type: "debug_resolved", payload: marker.payload)]
        case "mermaid_render":
            return [.raw(type: "mermaid_render", payload: marker.payload)]
        case "activate_plan_mode":
            return [.raw(type: "activate_plan_mode", payload: marker.payload)]
        case "activate_debug_mode":
            return [.raw(type: "activate_debug_mode", payload: marker.payload)]
        case "show_task_panel":
            return [.raw(type: "coderide_show_task_panel", payload: [:])]
        case "show_swarm_panel":
            return [.raw(type: "coderide_show_swarm_panel", payload: marker.payload)]
        default:
            break
        }

        // Subagent tools — execute inline during the agent's streaming loop.
        if toolName.hasPrefix("subagent_") {
            return await executeSubagentTool(toolName: toolName, marker: marker, context: context)
        }

        // Skill tool — invoke a local skill (SKILL.md) via a subagent
        if toolName == "skill" {
            return await executeSkillTool(marker: marker, context: context)
        }

        // All other tools — execute through UnifiedToolRuntime
        let call = ToolCall(
            id: marker.payload["id"] ?? UUID().uuidString,
            name: toolName,
            args: marker.payload,
            sourceProvider: id,
            swarmId: marker.payload["swarm_id"],
            scope: executionScope
        )
        return await runtime.execute(call, context: ToolExecutionContext(workspaceContext: context, policy: policy, executionScope: executionScope))
    }

    private func executeLegacyInvokeSwarmIfNeeded(
        marker: CoderIDEMarker,
        toolName: String,
        context: WorkspaceContext
    ) async -> [StreamEvent]? {
        let normalizedTool = ProviderToolEventMapper.normalizeToolIdentifier(toolName)

        // Legacy direct tool call: invoke_swarm(...)
        let isDirectLegacyInvoke = normalizedTool == "invoke_swarm"

        // Legacy MCP wrapper: mcp_call(tool: coderide_invoke_swarm | invoke_swarm, ...)
        let targetMCPTool = ProviderToolEventMapper.normalizeToolIdentifier(
            marker.payload["tool"] ?? marker.payload["mcp_tool"] ?? marker.payload["tool_name"] ?? ""
        )
        let isLegacyInvokeViaMCP = normalizedTool == "mcp_call" && targetMCPTool == "invoke_swarm"

        guard isDirectLegacyInvoke || isLegacyInvokeViaMCP else { return nil }

        guard subagentProviderFactory != nil else {
            return [.raw(type: "tool_validation_error", payload: [
                "id": marker.payload["id"] ?? UUID().uuidString,
                "name": toolName,
                "title": "invoke_swarm non supportato",
                "detail": "invoke_swarm è legacy; usa subagent_* (subagent_explorer/coder/reviewer/...).",
                "status": "failed",
                "error_code": "legacy_invoke_swarm_disabled",
            ])]
        }

        var adaptedPayload = marker.payload
        if (adaptedPayload["task"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let fallbackTask = adaptedPayload["prompt"]
                ?? adaptedPayload["detail"]
                ?? adaptedPayload["query"]
                ?? adaptedPayload["objective"]
                ?? adaptedPayload["goal"]
                ?? ""
            if !fallbackTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                adaptedPayload["task"] = fallbackTask
            }
        }

        guard let task = adaptedPayload["task"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !task.isEmpty else {
            return [.raw(type: "tool_validation_error", payload: [
                "id": marker.payload["id"] ?? UUID().uuidString,
                "name": toolName,
                "title": "Missing task",
                "detail": "invoke_swarm richiede un task non vuoto; usa subagent_* con task.",
                "status": "failed",
                "error_code": "missing_argument",
            ])]
        }

        let role = Self.resolveLegacyInvokeSwarmRole(payload: adaptedPayload, task: task)
        let mappedToolName = ProviderToolEventMapper.normalizeToolIdentifier(role.toolName)
        adaptedPayload["task"] = task
        adaptedPayload["name"] = mappedToolName
        adaptedPayload["tool"] = mappedToolName
        adaptedPayload["tool_name"] = mappedToolName

        let adaptedMarker = CoderIDEMarker(kind: marker.kind, payload: adaptedPayload)
        return await executeSubagentTool(
            toolName: mappedToolName,
            marker: adaptedMarker,
            context: context
        )
    }

    private static func resolveLegacyInvokeSwarmRole(
        payload: [String: String],
        task: String
    ) -> SubagentRole {
        let roleCandidates = [
            payload["role"],
            payload["agent"],
            payload["swarm"],
            payload["swarm_id"],
            payload["worker"],
            payload["type"],
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

        for candidate in roleCandidates where !candidate.isEmpty {
            let normalized = candidate
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
                .lowercased()
            if let fromToolName = SubagentRole.fromToolName("subagent_\(normalized)") {
                return fromToolName
            }
            if normalized.contains("review") { return .reviewer }
            if normalized.contains("debug") { return .debugger }
            if normalized.contains("test") { return .testWriter }
            if normalized.contains("doc") { return .docWriter }
            if normalized.contains("security") || normalized.contains("audit") { return .securityAuditor }
            if normalized.contains("code") || normalized.contains("implement") { return .coder }
            if normalized.contains("explore") || normalized.contains("research") || normalized.contains("analy") {
                return .explorer
            }
        }

        let taskText = task.lowercased()
        if taskText.contains("review") { return .reviewer }
        if taskText.contains("debug") || taskText.contains("bug") { return .debugger }
        if taskText.contains("test") { return .testWriter }
        if taskText.contains("doc") { return .docWriter }
        if taskText.contains("security") || taskText.contains("audit") { return .securityAuditor }
        if taskText.contains("implement") || taskText.contains("fix") || taskText.contains("code") {
            return .coder
        }
        return .explorer
    }

    private func enforcedMCPEditEventsIfNeeded(
        marker: CoderIDEMarker,
        toolName: String,
        context: WorkspaceContext
    ) async -> [StreamEvent]? {
        guard policy.enforceMCPEditOnly else { return nil }
        guard Self.mcpEditLikeTools.contains(toolName.lowercased()) else { return nil }

        guard policy.enableMCP else {
            return [
                mcpEditRequiredErrorEvent(
                    originalTool: toolName,
                    detail: "MCP-only editing is enforced, but MCP is disabled by policy.",
                    reroutedTool: nil
                )
            ]
        }

        guard let reroute = Self.rerouteEditToolToMCP(
            toolName: toolName,
            args: marker.payload
        ) else {
            return [
                mcpEditRequiredErrorEvent(
                    originalTool: toolName,
                    detail: "Tool '\(toolName)' is not reroutable to coderide MCP editing.",
                    reroutedTool: nil
                )
            ]
        }

        var reroutedArgs = reroute.args
        reroutedArgs["id"] = marker.payload["id"] ?? UUID().uuidString
        reroutedArgs["name"] = "mcp_call"
        reroutedArgs["tool"] = reroute.mcpTool
        reroutedArgs["server"] = "coderide"
        reroutedArgs["mcp_server"] = "coderide"
        reroutedArgs["mcp_tool"] = reroute.mcpTool

        let reroutedCall = ToolCall(
            id: reroutedArgs["id"] ?? UUID().uuidString,
            name: "mcp_call",
            args: reroutedArgs,
            sourceProvider: id,
            swarmId: marker.payload["swarm_id"],
            scope: executionScope
        )

        let produced = await runtime.execute(
            reroutedCall,
            context: ToolExecutionContext(
                workspaceContext: context,
                policy: policy,
                executionScope: executionScope
            )
        )

        if shouldEmitMCPEditRequiredAfterRerouteFailure(events: produced) {
            return [
                mcpEditRequiredErrorEvent(
                    originalTool: toolName,
                    detail: "Unable to use coderide MCP editing tool '\(reroute.mcpTool)'. Verify MCP server/tool availability.",
                    reroutedTool: reroute.mcpTool
                )
            ]
        }

        return produced
    }

    private func shouldEmitMCPEditRequiredAfterRerouteFailure(events: [StreamEvent]) -> Bool {
        for event in events {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "mcp_tool_call", payload["status"] == "completed" {
                return false
            }
            if type == "tool_execution_error" {
                let errorCode = (payload["error_code"] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if errorCode == "mcp_unavailable" || errorCode == "validation" {
                    return true
                }
            }
        }
        return false
    }

    private func mcpEditRequiredErrorEvent(
        originalTool: String,
        detail: String,
        reroutedTool: String?
    ) -> StreamEvent {
        var payload: [String: String] = [
            "title": "MCP-only editing policy violation",
            "detail": detail,
            "status": "failed",
            "error_code": "mcp_edit_required",
            "tool": originalTool,
        ]
        if let reroutedTool, !reroutedTool.isEmpty {
            payload["mcp_tool"] = reroutedTool
            payload["mcp_server"] = "coderide"
            payload["server_id"] = "coderide"
        }
        return .raw(type: "tool_validation_error", payload: payload)
    }

    struct MCPEditReroute: Sendable, Equatable {
        let mcpTool: String
        let args: [String: String]
    }

    static let mcpEditLikeTools: Set<String> = [
        "edit", "write", "str_replace", "regex_replace",
        "apply_patch", "create_file", "delete_file",
        "parallel_apply", "find_and_replace_all",
        "rename_symbol", "undo_edit", "multi_edit",
        "multiedit",
    ]

    static func rerouteEditToolToMCP(toolName: String, args: [String: String]) -> MCPEditReroute? {
        func required(_ key: String) -> String? {
            let value = (args[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : args[key]
        }

        switch toolName.lowercased() {
        case "write":
            guard let path = required("path"), let content = args["content"] else { return nil }
            return MCPEditReroute(mcpTool: "coderide_write", args: [
                "path": path,
                "content": content,
            ])
        case "edit":
            if let path = required("path"),
               let oldString = args["old_string"],
               !oldString.isEmpty,
               let newString = args["new_string"] {
                return MCPEditReroute(mcpTool: "coderide_str_replace", args: [
                    "path": path,
                    "old_string": oldString,
                    "new_string": newString,
                ])
            }
            if let path = required("path"),
               let content = args["content"] {
                return MCPEditReroute(mcpTool: "coderide_write", args: [
                    "path": path,
                    "content": content,
                ])
            }
            return nil
        case "str_replace":
            guard let path = required("path"),
                  let oldString = args["old_string"], !oldString.isEmpty,
                  let newString = args["new_string"] else { return nil }
            return MCPEditReroute(mcpTool: "coderide_str_replace", args: [
                "path": path,
                "old_string": oldString,
                "new_string": newString,
            ])
        case "regex_replace":
            guard let path = required("path"),
                  let pattern = args["pattern"], !pattern.isEmpty,
                  let replacement = args["replacement"] else { return nil }
            var reroutedArgs: [String: String] = [
                "path": path,
                "pattern": pattern,
                "replacement": replacement,
            ]
            if let flags = required("flags") {
                reroutedArgs["flags"] = flags
            }
            return MCPEditReroute(mcpTool: "coderide_regex_replace", args: reroutedArgs)
        case "create_file":
            guard let path = required("path"),
                  let content = args["content"] else { return nil }
            return MCPEditReroute(mcpTool: "coderide_create_file", args: [
                "path": path,
                "content": content,
            ])
        default:
            return nil
        }
    }

    private func inferredToolName(from payload: [String: String]) -> String {
        let supportedTools: Set<String> = [
            "read", "glob", "grep", "edit", "write", "bash", "mcp", "web_search", "web_fetch",
            "str_replace", "create_file", "delete_file", "apply_patch",
            "read_range", "list_dir", "git_diff", "search_symbols", "run_tests", "build_project",
            "list_processes", "read_json", "write_json", "workspace_stats", "dependency_audit",
            "tail_log", "mcp_call", "mcp_list_tools", "mcp_describe_tool", "mcp_health",
            "mcp_list_servers", "mcp_reconnect",
            "todo_write", "todo_read", "plan_step_update", "mermaid_render", "policy_ack",
            "activate_plan_mode", "activate_debug_mode", "show_task_panel", "invoke_swarm", "show_swarm_panel",
            "debug_set_phase", "debug_request_user", "debug_resolve",
            // Codebase index tools
            "codebase_search", "find_symbol", "list_symbols", "find_references",
            "project_structure", "file_outline", "find_files", "codebase_stats",
            "dependency_graph", "list_types", "list_tests", "index_status", "reindex",
            // New Cursor-style tools
            "parallel_apply", "regex_replace", "attempt_completion", "diagnostics",
            // Advanced tools
            "rename_symbol", "find_and_replace_all", "undo_edit", "run_single_test",
            // Debug tools
            "debug_log", "debug_query", "debug_session", "debug_hypothesize",
            "debug_mark", "debug_clean",
            // Cursor-style semantic tools
            "semantic_search", "read_lints", "debug_context",
            // Subagent and skill tools
            "skill",
            "subagent_explorer", "subagent_coder", "subagent_debugger", "subagent_reviewer",
            "subagent_testwriter", "subagent_docwriter", "subagent_securityauditor",
            // Legacy alias kept for backward compatibility
            "subagent_tester"
        ]
        let explicitCandidates = [
            payload["name"],
            payload["tool"],
            payload["tool_name"],
            payload["function"],
            payload["function_name"],
        ]
        for candidate in explicitCandidates {
            let rawName = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !rawName.isEmpty else { continue }
            let name = ProviderToolEventMapper.normalizeToolIdentifier(rawName)
            if name == "debug_panel" {
                // Legacy hard-cut: never execute, always route to validation error.
                return name
            }
            if name.hasPrefix("subagent_"), SubagentRole.fromToolName(name) != nil {
                return name
            }
            if supportedTools.contains(name) {
                return name
            }
        }

        if let command = payload["command"], !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "bash"
        }
        if let query = payload["query"], !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let scope = (payload["pathScope"] ?? payload["path_scope"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return scope.isEmpty ? "web_search" : "grep"
        }
        if let pattern = payload["pattern"], !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "glob"
        }
        if let content = payload["content"], !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "write"
        }
        if let path = payload["path"], !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "read"
        }
        return ""
    }

    private func shouldForceAutonomousContinuation(_ text: String, roundIndex: Int) -> Bool {
        if roundIndex >= maxAutonomousContinuationRounds { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if isMeaningfulAssistantCompletion(trimmed) {
            return false
        }
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        guard wordCount <= 260 else { return false }
        let lower = trimmed.lowercased()
        let explicitSignals = [
            "let me ",
            "i'll start",
            "i will start",
            "i'll begin",
            "i will begin",
            "exploring the",
            "analyzing the",
            "next i'll",
            "next i will",
            "would you like me to",
            "if you want i can",
            "i can continue by"
        ]
        if explicitSignals.contains(where: { lower.contains($0) }) {
            return true
        }
        if lower.hasSuffix("...") || lower.hasSuffix(":") {
            return true
        }
        return false
    }

    private static let blockedDeltaSnippets: [String] = [
        "Initial user prompt:",
        "Original user prompt:",
        "Partial transcript:",
        "Conversation transcript:",
        "Transcript:",
        "Tool results just executed:",
        "Tool results from previous round:",
        "When finished: MANDATORY",
        "When finished: you MUST provide",
        "(No tools used in the previous round.)",
        "[assistant]",
    ]

    private func sanitizeVisibleDelta(_ delta: String) -> String {
        if delta.isEmpty { return "" }
        let lower = delta.lowercased()
        for snippet in Self.blockedDeltaSnippets where lower.contains(snippet.lowercased()) {
            return ""
        }
        return delta
    }

    private func buildToolFallbackSummary(_ results: [[String: String]]) -> String {
        let lines = results.prefix(8).map { item in
            let name = item["name"] ?? "tool"
            let status = item["status"] ?? "unknown"
            let detail = item["detail"] ?? ""
            let path = item["path"] ?? ""
            var line = "- \(name): \(status)"
            if !detail.isEmpty { line += " — \(detail)" }
            if !path.isEmpty { line += " (\(path))" }
            return line
        }
        guard !lines.isEmpty else { return "" }
        return """

        **Summary:**
        \(lines.joined(separator: "\n"))

        """
    }

    private func buildForcedFinalizationPrompt(
        originalPrompt: String,
        transcript: String,
        toolResults: [[String: String]]
    ) -> String {
        let compactResults = toolResults.prefix(10).map { item in
            let name = item["name"] ?? "tool"
            let status = item["status"] ?? "unknown"
            let detail = item["detail"] ?? ""
            return "- \(name): \(status) \(detail)"
        }.joined(separator: "\n")
        return """
        You have already executed the required tools. Now you MUST produce ONLY the final outcome for the user.
        Mandatory rules:
        1) Do NOT emit any more tool markers.
        2) Do NOT stop until you write a complete final summary.
        3) If any data is missing, state what's missing and propose a concrete next step.

        Original user prompt:
        \(originalPrompt)

        Transcript:
        \(transcript)

        Tool results:
        \(compactResults)
        """
    }

    private func isMeaningfulAssistantCompletion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 24 { return false }
        let lower = trimmed.lowercased()
        let blocked = [
            "tool results just executed",
            "tool results from previous round",
            "initial user prompt",
            "original user prompt:",
            "partial transcript",
            "conversation transcript:",
            "codieride:tool_call",
            "[assistant]",
        ]
        for snippet in blocked where lower.contains(snippet) {
            return false
        }
        return true
    }

    /// Generates the system prompt section listing all natively-registered MCP tools, grouped by server.
    private var mcpNativeToolsPromptSection: String {
        let registry = MCPNativeToolRegistry.shared
        let entries = registry.entries
        guard !entries.isEmpty else {
            return "No MCP tools currently available. Use `mcp_list_servers` and `mcp_list_tools` to discover tools at runtime."
        }

        let routing = registry.routing
        var serverTools: [String: [(functionName: String, entry: ToolSchemaEntry)]] = [:]
        for entry in entries {
            let serverName: String
            if let route = routing[entry.name] {
                serverName = route.serverId
            } else {
                serverName = "unknown"
            }
            serverTools[serverName, default: []].append((functionName: entry.name, entry: entry))
        }

        var lines: [String] = []
        lines.append("**Available MCP tools** (call directly by function name):")
        for (server, tools) in serverTools.sorted(by: { $0.key < $1.key }) {
            lines.append("")
            let displayServer = server.components(separatedBy: "|").last ?? server
            lines.append("Server: **\(displayServer)**")
            for tool in tools {
                let params = tool.entry.required.isEmpty
                    ? ""
                    : " Args: \(tool.entry.required.map { "`\($0)`" }.joined(separator: ", "))."
                let desc = tool.entry.description
                    .replacingOccurrences(of: "[\(displayServer)] ", with: "")
                    .replacingOccurrences(of: "[\(server)] ", with: "")
                lines.append("- **\(tool.functionName)** — \(desc)\(params)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private var toolProtocolPrompt: String {
        """
        # Tool Protocol

        You have access to powerful tools. Use tool calls to execute them.

        ## Mandatory Execution Workflow
        For EVERY task, follow this sequence strictly:
        1. **INVESTIGATE** — Use search/read tools (semantic_search, codebase_search, grep, glob, find_symbol, find_references, read, file_outline, web_search) to understand the problem BEFORE making changes.
        2. **REPORT** — State what you found: problems, root causes, affected files, scope. Be explicit.
        3. **TODO LIST** — For multi-step tasks, use the `todo_write` tool to create a structured task list in the LiveCard. This is mandatory for tasks with 3+ steps.
        4. **RESOLVE** — Fix issues one by one following the todo list. After each fix, verify. Update todo status as you go.
        5. **VERIFY & SUMMARIZE** — Run final verification. Report: what changed, which files, outcome.

        ## Core Principles
        1. ALWAYS read a file before editing it — understand current content first.
        2. Use `str_replace` for surgical edits (search-and-replace). ONLY use `write` for brand new files or complete rewrites.
        3. Prefer `semantic_search` for natural language queries ("where is auth handled?", "data saving flow").
        4. Prefer `codebase_search` and `find_symbol` over `grep` when looking for symbol definitions (classes, functions, structs). They use the index and are faster and more precise.
        5. Use `grep` for text/regex search. Use `glob` to find files by name pattern. Use `find_files` for fuzzy file name matching.
        6. Use `file_outline` to understand a file's structure before reading it entirely.
        7. Use `find_references` before refactoring to understand all usages of a symbol.
        8. Use `bash` ONLY for git operations, running commands, installing dependencies, builds, tests. Do NOT use bash for file operations (reading, searching, editing) — use the dedicated tools instead.
        9. After making changes, verify with `read_lints` (fast, no build) or `diagnostics` (full build). Prefer `read_lints` for quick checks.
        10. Use `parallel_apply` for making multiple independent edits across files in a single call.
        11. If AGENTS.md / SKILL.md / repository runbooks or **Detected local skills** are present, USE the `skill` tool when the task matches. Skills (doc, imagegen, transcribe, playwright, etc.) provide optimized workflows — invoke them instead of reinventing.
        12. If the context contains a mandatory policy acknowledgment, use the `policy_ack` tool with the hash before any operational tool action.
        13. MCP tools from connected servers are registered as native function tools — call them directly by name. Use `mcp_call` only for tools not registered natively. Use `mcp_list_tools` if you need to discover additional tools at runtime.
        14. Use `web_search` and `web_fetch` when you need current information, documentation, API references, or anything beyond your training data.
        15. When done, provide a clear summary: what changed, which files, outcome.
        16. Do NOT stop until the task is fully resolved or you've clearly stated a blocker with next steps.

        ## Available Tools

        ### File Operations
        - **read** — Read a file with line numbers. Args: `path`.
        - **str_replace** — Replace exact text in a file. Args: `path`, `old_string`, `new_string`.
          The `old_string` MUST match EXACTLY (including whitespace/indentation).
          If it appears multiple times, add more surrounding context lines to make it unique.
          ALWAYS prefer `str_replace` over `write` for editing existing files.
        - **write** — Write entire file content. ONLY for new files or complete rewrites. Args: `path`, `content`.
        - **create_file** — Create a new file (fails if file exists). Args: `path`, `content`.
        - **read_range** — Read specific line range. Args: `path`, `start`, `end`.
        - **list_dir** — List directory contents. Args: `path`.

        ### Search & Navigation
        - **semantic_search** — Search code by meaning/intent using BM25 semantic index with AST-aware chunking. Use for questions like "where is authentication handled?", "data saving flow", "error handling logic". Understands synonyms (auth→login, save→persist), camelCase splitting, symbol names, scope context. Args: `query` (natural language), `target_directories` (optional comma-separated dirs), `num_results` (1-50, default 25).
        - **grep** — Regex search (powered by ripgrep). Args: `query`, `pathScope` (dir), `fileType` (e.g. swift/ts/py), `context_lines` (0-10), `case_sensitive` (true/false), `multiline` (true/false).
        - **glob** — Find files by glob pattern. Args: `pattern` (e.g. `*.swift`, `**/*Test*`), `path` (scope dir).
        - **search_symbols** — Search code symbols across all languages. Args: `query`, `kind`.

        ### Codebase Index (index-powered, faster and more precise than grep for symbol search)
        - **codebase_search** — Search symbols by name, kind, or pattern using the structured index. Much faster than grep for finding definitions. Args: `query`, `kind` (class/struct/enum/protocol/function/method/property/test/all), `filePattern` (optional glob).
        - **find_symbol** — Find exact symbol definitions. Args: `query`, `kind` (optional).
        - **list_symbols** — List all symbols in a file (file outline with types, functions, properties). Args: `path`.
        - **find_references** — Find all references to a symbol (definitions + usages). Args: `query`.
        - **project_structure** — Show project file tree. Args: `maxDepth` (default 3).
        - **file_outline** — Structured outline of a file with line numbers. Args: `path`.
        - **find_files** — Fuzzy file finder (faster than glob for name matching). Args: `query`, `extension` (optional).
        - **codebase_stats** — Codebase statistics: files, languages, sizes, symbols.
        - **dependency_graph** — Show imports and dependents of a file. Args: `path`.
        - **list_types** — List all types (class, struct, enum, protocol) in the codebase.
        - **list_tests** — List all tests in the codebase.
        - **index_status** — Show index health and stats.
        - **reindex** — Force re-indexing the workspace.

        ### Advanced Editing
        - **multi_edit** — Apply multiple edits to a single file atomically. All edits are validated first; if any old_string is not found or not unique, no changes are made. Args: `path`, `edits` (JSON array: `[{"old_string": "...", "new_string": "..."}]`). Use this when making several related changes to the same file — faster and safer than multiple str_replace calls.
        - **parallel_apply** — Multiple str_replace edits across DIFFERENT files in one call. Args: `edits` (JSON array of objects, each with `path`, `old_string`, `new_string`).
        - **regex_replace** — Regex-based find-and-replace. Args: `path`, `pattern` (regex), `replacement` (supports $1 capture groups), `flags` (optional: i=case-insensitive, m=multiline, s=dotall).
        - **rename_symbol** — Rename a symbol across the entire codebase. Uses the index to find all references, then replaces. Args: `old_name`, `new_name`, `kind` (optional: class/function/etc).
        - **find_and_replace_all** — Workspace-wide find-and-replace across all files. Args: `search` (string or regex), `replacement`, `filePattern` (optional glob like *.swift), `is_regex` (optional: true/false).
        - **undo_edit** — Revert a file to its last committed state (git checkout). Args: `path`.

        ### Code Context
        - **related_files** — Find files related to a given file: test files, import dependencies, dependents, similarly-named files, siblings. Essential before editing to understand context. Args: `path`.
        - **git_log_search** — Search git history for commits that introduced or removed code patterns (git pickaxe). Also searches commit messages. Args: `query`, `path` (optional file/dir filter), `author` (optional), `since` (optional date), `limit` (default 20).

        ### Execution
        - **bash** — Run shell command. Args: `command`, `cwd`.
        - **git_diff** — Show git diff. Args: `path`.
        - **run_tests** — Run tests. Args: `target`, `filter`.
        - **run_single_test** — Run a single test by name. Auto-detects project type (Swift/Node/Cargo/Go). Args: `test_name`, `file` (optional).
        - **build_project** — Build project. Args: `configuration`, `target`.
        - **diagnostics** — Get build errors/warnings as structured output (runs full build). Args: `manager` (swift/npm/cargo/go, auto-detected if omitted).
        - **read_lints** — Read current linter/diagnostic state WITHOUT running a full build. Much faster than `diagnostics`. Auto-detects project type. Args: `path` (optional: check single file), `severity` (all/error/warning), `limit` (default 50).
        - **attempt_completion** — Signal task completion. Args: `result` (summary), `command` (optional verification command to run).

        ### Data
        - **read_json** — Read and pretty-print JSON. Args: `path`.
        - **write_json** — Merge patch into JSON file. Args: `path`, `patch`.

        ### Skill (local SKILL.md workflows)
        - **skill** — Invoke a local skill from ~/.codex/skills, ~/.claude/skills, or ~/.agents/skills. Use when the task matches a skill's description (doc, imagegen, transcribe, playwright, cloudflare-deploy, gh-fix-ci, etc.). Args: `skill` or `name` (skill name), `task` or `args` (what to do). ALWAYS prefer skills over manual workflows when a skill exists for the task.

        ### MCP (Model Context Protocol)
        MCP tools from connected servers are registered as **native function tools** — call them directly by name without any discovery steps.

        \(mcpNativeToolsPromptSection)

        **Fallback/admin tools** (only use when native tools are insufficient):
        - **mcp_call** — Call an MCP tool by name. Pass tool arguments as top-level key-value pairs alongside `tool` and `server`. Args: `server` (server ID), `tool` (tool name), plus the tool's own arguments as top-level keys.
        - **mcp_list_tools** — List available MCP tools. Args: `server` (optional, filter by server).
        - **mcp_describe_tool** — Get the full JSON Schema for an MCP tool. Args: `tool`, `server` (optional).
        - **mcp_list_servers** — List all connected MCP servers.
        - **mcp_health** — Check MCP server connection health.
        - **mcp_reconnect** — Force reconnect to a server. Args: `server`.

        **MCP best practices:**
        - Call native MCP tools directly — no discovery needed, schemas are already registered.
        - Only use `mcp_call` for tools that aren't registered natively (rare).
        - If a native MCP tool call fails with "not found", the server may have restarted — use `mcp_reconnect` then retry.
        - MCP tools can be called in parallel with other tools when they are read-only.

        ### Web Tools
        - **web_search** — Search the web for current information. Returns a JSON array of results, each with `title`, `snippet`, and `url`. Use when you need up-to-date information, current documentation, recent API changes, external references, or anything beyond your training data. Args: `query` (search terms), `explanation` (optional context for the search).
        - **web_fetch** — Fetch a web page and return its content as clean Markdown. Downloads the page HTML and converts it to readable Markdown, stripping scripts, styles, navigation, and non-content elements. Use to read full documentation pages, blog posts, Stack Overflow answers, API references, changelogs, or any URL. Args: `url` (the full URL to fetch). Limits: 128KB download, 12K chars output. Only supports public HTTP(S) pages (no localhost, no auth-protected pages, no binary files).

        **Web tools workflow — always follow this pattern:**
        1. Use `web_search` with a precise query to find relevant URLs and snippets.
        2. Review the search results (titles + snippets) to identify the most promising pages.
        3. Use `web_fetch` on the best 1-3 URLs to read their full content.
        4. Synthesize the information from fetched pages into your response, citing sources.

        **When to use web tools:**
        - Current events, news, recent releases
        - Up-to-date documentation, API references, changelogs
        - Stack Overflow solutions, GitHub issues, blog posts
        - Verifying information that may have changed since training
        - Any time the user asks to "search", "look up", "check online", or provides a URL

        **Best practices:**
        - Write precise search queries (e.g., "Swift URLSession async await timeout" not just "Swift networking")
        - Run multiple searches if covering different aspects
        - Prioritize official sources (docs, repos) over third-party
        - Fetch multiple URLs in parallel when possible (they are read-only tools)
        - Always cite the source URLs in your response
        - If a fetch fails (404, timeout), try an alternative URL from search results

        ### Debug Tools (for debug mode — analyzing bugs, forming hypotheses, tracking investigation)
        - **debug_context** — Gather full debug context in one call: git status, open files, lint errors, recent commits, debug log summary. Use this FIRST when entering debug mode. No required args.
        - **debug_log** — Write an entry to the debug log server. Args: `severity` (error/warning/info/verbose/trace), `source` (file:line or module), `message`, `detail` (optional: stack trace), `category` (optional: compiler/runtime/test/network/custom).
        - **debug_query** — Query the debug log. Args: `severity` (optional filter), `category` (optional), `source` (optional), `search` (text search), `format` (summary/full, default: summary), `limit` (default 100).
        - **debug_session** — Manage debug sessions. Args: `action` (start/end/clear).
        - **debug_hypothesize** — Propose or update a debug hypothesis (ID-based). Args: `action` (propose/update), `hypothesis_id` (required for update), `title` (required for propose), `description`, `status` (proposed/investigating/confirmed/rejected), `evidence`.
        - **debug_mark** — Insert a debug marker (print/log/assert) into a file. The marker is tagged with 🐛 DEBUG for easy cleanup. Args: `path`, `line` (line number), `comment` (description), `code` (optional code to insert).
        - **debug_clean** — Remove ALL debug markers (lines containing 🐛 DEBUG) from a file or entire workspace. Args: `path` (optional, cleans all files if omitted).

        ### Debug Flow (MCP-first, typed events)
        When debugging, use only the canonical typed debug tools for panel control:
        - `debug_set_phase` (phase: describing|reproducing|fixing|instrumenting|verifying|resolved, detail optional)
        - `debug_request_user` (kind: question|reproduce, prompt)
        - `debug_resolve` (summary)
        - `debug_panel` is legacy and invalid.

        **Phase 1: Describe**
        1. `debug_set_phase phase=describing`
        2. Gather context with `debug_context`
        3. Start/ensure session with `debug_session action=start`
        4. Log symptoms with `debug_log`

        **Phase 2: Reproduce**
        5. `debug_set_phase phase=reproducing`
        6. If user action is needed, call `debug_request_user kind=reproduce prompt=...`

        **Phase 3: Fix**
        7. `debug_set_phase phase=fixing`
        8. Hypothesize with `debug_hypothesize`
        9. Instrument with `debug_mark` and `debug_set_phase phase=instrumenting` when relevant
        10. Observe via `debug_log` + `debug_query`
        11. Apply minimal fix and update hypothesis status

        **Phase 4: Verify**
        12. `debug_set_phase phase=verifying`
        13. Verify via `read_lints` and targeted tests/diagnostics
        14. Clean instrumentation with `debug_clean`

        **Phase 5: Resolve**
        15. Resolve with `debug_resolve summary=...`
        16. Optionally mirror terminal phase with `debug_set_phase phase=resolved`

        ### Utility
        - **workspace_stats** — Get file/dir counts and size.
        - **dependency_audit** — Audit dependencies. Args: `manager` (swift/npm/pnpm/yarn).
        - **tail_log** — Read last N lines of a file. Args: `path`, `lines`.
        - **list_processes** — List running processes. Args: `filter`.

        ### IDE State Tools (LiveCard / panel control)
        - **todo_write** — Create or update a todo item in the LiveCard. Args: `title`, `status` (pending/in_progress/done/blocked), `priority` (low/medium/high), `notes` (optional), `activeForm` (optional present-tense label), `linkedFiles` (optional file paths).
        - **todo_read** — Read the current todo list. No required args.
        - **plan_step_update** — Update a plan step status. Args: `step_id`, `status` (pending/running/done/failed), `title` (optional).
        - **mermaid_render** — Render a Mermaid diagram in the LiveCard. Args: `code` (Mermaid syntax), `title` (optional).
        - **debug_set_phase** — Set debug pipeline phase. Args: `phase`, `detail` (optional).
        - **debug_request_user** — Request explicit user input in debug flow. Args: `kind` (question/reproduce), `prompt`.
        - **debug_resolve** — Resolve debug flow with summary. Args: `summary`.
        - **policy_ack** — Acknowledge a mandatory policy hash. Args: `hash`.
        - **activate_plan_mode** — Activate the plan panel. Args: `reason` (optional).
        - **activate_debug_mode** — Activate the debug panel. Args: `reason` (optional).
        - **show_task_panel** — Show the task panel. No required args.
        - **show_swarm_panel** — Open/focus swarm panel. Args: `swarm_id` (optional).

        \(subagentProviderFactory != nil ? """
        ### Subagent Tools — MANDATORY PARALLEL EXECUTION (you MUST use these)
        - **subagent_explorer** — Spawn a read-only exploration subagent. Searches, reads, analyzes code — CANNOT edit. Runs on Codex/Claude/Gemini/OpenAI/etc. Call 2–3 explorers in the SAME round for parallel investigation. Args: `task`.
        - **subagent_coder** — Spawn a coding subagent with full tool access (edit, bash, etc.). Each coder works on a different file/module in parallel. Args: `task`.
        - **subagent_reviewer** — Spawn a code review subagent. Reviews quality, bugs, style. Args: `task`.
        - **subagent_debugger** — Spawn a debugger subagent. Investigates and fixes bugs. Args: `task`.
        - **subagent_testWriter** — Spawn a test-writing subagent. Args: `task`.
        - **subagent_docWriter** — Spawn a documentation subagent. Args: `task`.
        - **subagent_securityAuditor** — Spawn a security audit subagent. Args: `task`.

        ⚠️ MANDATORY PARALLEL EXECUTION POLICY — NON-NEGOTIABLE ⚠️
        - You are the ORCHESTRATOR. You COORDINATE and DELEGATE — you do NOT do implementation work yourself.
        - Subagents run on DIFFERENT backends (Codex, Claude, Gemini, OpenAI, Anthropic, Google, OpenRouter, MiniMax, Grok) in PARALLEL. Each call in the same round goes to a different backend automatically.
        - You MUST call 2–5 subagents in the SAME round for ANY task with multiple independent parts.
        - You MUST spawn subagents in your FIRST tool round. Do NOT waste rounds doing manual grep/read/edit.
        - Explorer subagents are lightweight (read-only) — spawn them freely and in bulk (2–3 per round).
        - For implementation: spawn multiple subagent_coder instances, each assigned to a different file or module.
        - AFTER implementation: you MUST spawn subagent_reviewer + subagent_testWriter in parallel. This is mandatory.
        - NEVER do work sequentially that can be parallelized across subagents.
        - After subagent results return, immediately update todos via todo_write.

        CORRECT pattern (3 rounds, maximum parallelism):
          Round 1: subagent_explorer("investigate data model") + subagent_explorer("investigate UI layer") + subagent_explorer("investigate tests")
          Round 2: TodoWrite → subagent_coder("implement model changes") + subagent_coder("implement UI changes")
          Round 3: subagent_reviewer("review all changes") + subagent_testWriter("write tests for changes")

        WRONG pattern (sequential, no parallelism):
          Round 1: grep for files...
          Round 2: read file A...
          Round 3: read file B...
          Round 4: edit file A...
          Round 5: edit file B...
          This is FORBIDDEN. Use subagents instead.
        """ : "Subagent delegation is not available in this configuration. Use tools directly to complete your task.")
        """
    }

    // MARK: - Parallel Tool Execution

    /// Tools that only read data and can safely run concurrently
    private static let readOnlyToolNames: Set<String> = [
        "read", "glob", "grep", "codebase_search", "find_symbol", "list_symbols",
        "find_references", "project_structure", "file_outline", "find_files",
        "codebase_stats", "dependency_graph", "list_types", "list_tests",
        "index_status", "read_range", "list_dir", "git_diff", "read_json",
        "workspace_stats", "tail_log", "list_processes", "search_symbols",
        "mcp_list_tools", "mcp_describe_tool", "mcp_list_servers", "mcp_health",
        "debug_query", "semantic_search", "related_files", "git_log_search",
        "read_lints", "debug_context",
        "batch_read", "diff_files", "git_status", "git_show", "code_context",
        "web_search", "web_fetch",
        "subagent_explorer",
    ]

    // MARK: - Real-time tool start events

    /// Maps a tool name to the event type used for its "started" trace event.
    /// These types must pass ToolTraceVisibility and have isRunning == true.
    private static func toolStartEventType(for toolName: String) -> String {
        switch toolName {
        case "bash":
            return "command_execution"
        case "edit", "write", "str_replace", "create_file", "delete_file", "parallel_apply", "regex_replace",
             "apply_patch", "multi_edit", "multiedit",
             "rename_symbol", "find_and_replace_all", "undo_edit":
            return "file_change"
        case "web_search":
            return "web_search_started"
        case "web_fetch":
            return "web_fetch_started"
        case _ where toolName.hasPrefix("subagent_"):
            return "agent"
        case "skill":
            return "skill_invocation"
        default:
            return "read_batch_started"
        }
    }

    /// Builds a payload for the real-time "started" event emitted before tool execution.
    private static func toolStartPayload(for toolName: String, args: [String: String]) -> [String: String] {
        var payload: [String: String] = [
            "tool": toolName,
            "name": toolName,
            "status": "started",
            "tool_call_id": args["id"] ?? "",
        ]
        if let command = args["command"], !command.isEmpty {
            payload["command"] = command
            payload["title"] = "Bash"
            payload["detail"] = command
        }
        if let path = args["path"], !path.isEmpty { payload["path"] = path }
        if let query = args["query"], !query.isEmpty { payload["query"] = query }
        if let url = args["url"], !url.isEmpty { payload["url"] = url }
        if let server = args["server"] ?? args["server_id"], !server.isEmpty {
            payload["server_id"] = server
            payload["mcp_server"] = server
        }
        if let swarmId = args["swarm_id"], !swarmId.isEmpty {
            payload["swarm_id"] = swarmId
            payload["group_id"] = "swarm-\(swarmId)"
        }
        if toolName == "skill", let skillName = args["skill"] ?? args["name"], !skillName.isEmpty {
            payload["skill"] = skillName
        }
        if payload["title"] == nil {
            payload["title"] = toolStartTitle(for: toolName, args: args)
        }
        return payload
    }

    private static func toolStartTitle(for toolName: String, args: [String: String]) -> String {
        let pathComponent = { (key: String) -> String in
            ((args[key] ?? "") as NSString).lastPathComponent
        }
        switch toolName {
        case "bash":
            return "Bash"
        case "edit", "str_replace":
            let file = pathComponent("path")
            return file.isEmpty ? "Edit" : "Edit • \(file)"
        case "write", "create_file":
            let file = pathComponent("path")
            return file.isEmpty ? "Write" : "Write • \(file)"
        case "read", "read_range":
            let file = pathComponent("path")
            return file.isEmpty ? "Read" : "Read • \(file)"
        case "glob":
            let pattern = args["pattern"] ?? ""
            return pattern.isEmpty ? "Glob" : "Glob • \(pattern)"
        case "grep":
            let query = args["query"] ?? ""
            return query.isEmpty ? "Grep" : "Grep • \(query)"
        case "semantic_search":
            return "Semantic search"
        case "codebase_search":
            return "Codebase search"
        case "find_symbol":
            return "Find symbol"
        case "find_references":
            return "Find references"
        case "web_search":
            return "Web search"
        case "web_fetch":
            return "Fetching web page"
        case "diagnostics":
            return "Diagnostics"
        case "build_project":
            return "Building project"
        case "run_tests", "run_single_test":
            return "Running tests"
        case "skill":
            let name = args["skill"] ?? args["name"] ?? ""
            return name.isEmpty ? "Skill" : "Skill • \(name)"
        default:
            if toolName.hasPrefix("subagent_") {
                let role = SubagentRole.fromToolName(toolName)
                return role.map { "\($0.displayName) subagent" } ?? toolName
            }
            return toolName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Inline Subagent Execution

    /// Execute a subagent tool inline during the agent's streaming loop.
    /// The subagent runs to completion using its own ToolEnabledLLMProvider instance,
    /// then returns the result as tool output events.
    private func executeSubagentTool(
        toolName: String,
        marker: CoderIDEMarker,
        context: WorkspaceContext
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

        let subagentId = "\(role.rawValue)-\(UUID().uuidString.prefix(8))"
        let toolCallId = marker.payload["id"] ?? UUID().uuidString
        var events: [StreamEvent] = []

        // Emit started event for SwarmLiveReducer UI
        events.append(.raw(type: "agent", payload: [
            "title": role.displayName,
            "detail": "started",
            "swarm_id": subagentId,
            "group_id": "swarm-\(subagentId)",
            "tool_call_id": toolCallId,
            "status": "started"
        ]))

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
            let stream = try await subagentProvider.send(
                prompt: prompt, context: context, imageURLs: nil
            )
            for try await event in stream {
                switch event {
                case .textDelta(let delta):
                    if fullTextLength + delta.count <= 50_000 { fullTextParts.append(delta); fullTextLength += delta.count }
                case .raw(let type, var payload):
                    // Enrich all raw events with subagent routing info
                    payload["swarm_id"] = subagentId
                    payload["group_id"] = "swarm-\(subagentId)"
                    events.append(.raw(type: type, payload: payload))
                default:
                    break
                }
            }

            let durationMs = Int(Date().timeIntervalSince(startDate) * 1000)
            let output = String(fullTextParts.joined().prefix(8000))

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

    /// Execute the skill tool by spawning a subagent with the skill's SKILL.md instructions.
    private func executeSkillTool(marker: CoderIDEMarker, context: WorkspaceContext) async -> [StreamEvent] {
        let skillName = marker.payload["skill"] ?? marker.payload["name"] ?? marker.payload["skill_name"] ?? ""
        let task = marker.payload["task"] ?? marker.payload["prompt"] ?? marker.payload["args"] ?? ""
        let toolCallId = marker.payload["id"] ?? UUID().uuidString
        let skillId = "skill-\(skillName)-\(UUID().uuidString.prefix(8))"
        var events: [StreamEvent] = []

        guard !skillName.isEmpty else {
            return [.raw(type: "tool_validation_error", payload: [
                "id": toolCallId,
                "name": "skill",
                "title": "Missing skill name",
                "detail": "skill tool requires 'skill' or 'name' (e.g. doc, imagegen, transcribe). Use mcp_list_tools to discover available skills.",
                "status": "failed",
                "error_code": "missing_argument"
            ])]
        }

        guard let skillContent = InstructionPolicyBundle.skillContent(for: skillName) else {
            return [.raw(type: "tool_validation_error", payload: [
                "id": toolCallId,
                "name": "skill",
                "title": "Skill not found",
                "detail": "No skill '\(skillName)' in ~/.codex/skills, ~/.claude/skills, or ~/.agents/skills. Install with the skill-installer skill.",
                "status": "failed",
                "error_code": "skill_not_found"
            ])]
        }

        events.append(.raw(type: "agent", payload: [
            "title": "Skill: \(skillName)",
            "detail": "started",
            "swarm_id": skillId,
            "group_id": "swarm-\(skillId)",
            "tool_call_id": toolCallId,
            "status": "started"
        ]))

        let startDate = Date()
        let userPrompt = task.isEmpty
            ? "Execute this skill according to its instructions. If the user's request is in the conversation context, use that."
            : task

        do {
            let subagentBase = subagentProviderFactory?() ?? base
            let subagentRuntime = UnifiedToolRuntime(
                executionController: nil,
                executionScope: .swarm,
                workspacePaths: context.workspacePaths
            )
            let subagentProvider = ToolEnabledLLMProvider(
                base: subagentBase,
                runtime: subagentRuntime,
                policy: policy,
                executionScope: .swarm,
                maxToolRounds: 120,
                subagentProviderFactory: nil
            )
            let systemPrompt = """
            You are executing the **\(skillName)** skill. Follow these instructions exactly:

            \(skillContent)

            Execute the user's task using the tools available to you (read, grep, bash, etc.).
            """
            let fullPrompt = "\(systemPrompt)\n\n---\n\n**Task:** \(userPrompt)"

            var fullTextParts: [String] = []
            var fullTextLength = 0
            let stream = try await subagentProvider.send(
                prompt: fullPrompt, context: context, imageURLs: nil
            )
            for try await event in stream {
                switch event {
                case .textDelta(let delta):
                    if fullTextLength + delta.count <= 50_000 {
                        fullTextParts.append(delta)
                        fullTextLength += delta.count
                    }
                case .raw(let type, var payload):
                    payload["swarm_id"] = skillId
                    payload["group_id"] = "swarm-\(skillId)"
                    events.append(.raw(type: type, payload: payload))
                default:
                    break
                }
            }

            let durationMs = Int(Date().timeIntervalSince(startDate) * 1000)
            let output = String(fullTextParts.joined().prefix(12000))

            events.append(.raw(type: "agent", payload: [
                "title": "Skill: \(skillName)",
                "detail": "completed",
                "swarm_id": skillId,
                "group_id": "swarm-\(skillId)",
                "tool_call_id": toolCallId,
                "status": "completed",
                "duration_ms": "\(durationMs)"
            ]))
            events.append(.raw(type: "tool_result", payload: [
                "id": toolCallId,
                "name": "skill",
                "title": "\(skillName) completed",
                "detail": "Skill \(skillName) completed in \(durationMs)ms",
                "output": output,
                "status": "success",
                "skill": skillName,
                "duration_ms": "\(durationMs)"
            ]))
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startDate) * 1000)
            events.append(.raw(type: "agent", payload: [
                "title": "Skill: \(skillName)",
                "detail": "failed",
                "swarm_id": skillId,
                "group_id": "swarm-\(skillId)",
                "tool_call_id": toolCallId,
                "status": "failed"
            ]))
            events.append(.raw(type: "tool_result", payload: [
                "id": toolCallId,
                "name": "skill",
                "title": "\(skillName) failed",
                "detail": error.localizedDescription,
                "output": "Skill \(skillName) failed: \(error.localizedDescription)",
                "status": "failed",
                "skill": skillName,
                "duration_ms": "\(durationMs)"
            ]))
        }

        return events
    }
}
