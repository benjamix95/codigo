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

    let base: any LLMProvider
    let runtime: UnifiedToolRuntime
    let policy: ToolRuntimePolicy
    let executionScope: ExecutionScope
    let maxToolRounds: Int
    let maxAutonomousContinuationRounds = 4

    /// Optional factory for creating base LLM providers for subagent execution.
    /// If nil, subagents reuse the same base provider as the parent agent.
    let subagentProviderFactory: (@Sendable () -> any LLMProvider)?

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

    public func setBrowserBridge(_ bridge: (any BrowserBridge)?) async {
        await runtime.setBrowserBridge(bridge)
    }

    public func setTerminalBridge(_ bridge: (any TerminalBridge)?) async {
        await runtime.setTerminalBridge(bridge)
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        // When systemPromptOverride is set (e.g. prompt optimization), pass through to base without
        // adding taskCompletionStrict or toolProtocolPrompt — the context carries the custom system prompt.
        if context.systemPromptOverride != nil {
            return try await base.send(prompt: prompt, context: context, imageURLs: imageURLs)
        }

        // Keep native MCP tool registry aligned with current server/config state.
        // Registering is idempotent when the discovered tool set did not change.
        if policy.enableMCP {
            let discovered = await runtime.mcpSessions.discoverAllTools(
                idleTTLSeconds: policy.mcpSessionIdleTTLSeconds
            )
            _ = MCPNativeToolRegistry.shared.register(tools: discovered)
        } else if MCPNativeToolRegistry.shared.hasTools() {
            MCPNativeToolRegistry.shared.clear()
        }

        let initialPrompt = """
        \(SystemPrompts.taskCompletionStrict)

        \(toolProtocolPrompt)

        \(prompt)
        """

        return AsyncThrowingStream { continuation in
            let producerTask = Task {
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
                        try Task.checkCancellation()
                        await runtime.resetRoundCounters()
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
                            case .textReplace(let replacement):
                                roundTextParts = replacement.isEmpty ? [] : [replacement]
                                roundTextLength = replacement.count
                                continuation.yield(.textReplace(replacement))
                            case .started:
                                if isFirstRound {
                                    continuation.yield(.started)
                                }
                            case .completed:
                                break
                            case .error:
                                continuation.yield(event)
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

                                    if !policy.allowMutatingTools,
                                       Self.toolWouldMutate(toolName: name, args: args) {
                                        continuation.yield(.raw(type: "tool_validation_error", payload: [
                                            "title": "Read-only phase policy",
                                            "detail": "Tool '\(name)' is blocked in read-only mode.",
                                            "status": "failed",
                                            "error_code": "read_only_violation",
                                            "tool": name,
                                        ]))
                                        continue
                                    }

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
                            }
                        }

                        // Execute deferred subagent calls in parallel via withTaskGroup.
                        // Emit "started" events for ALL subagents upfront so live cards
                        // appear in the chat immediately, then stream results as each
                        // subagent completes (rather than waiting for all to finish).
                        if !pendingSubagentCalls.isEmpty {
                            let calls = pendingSubagentCalls

                            // Pre-generate stable subagent IDs and emit "started" events
                            // before execution so the UI can show live cards right away.
                            var subagentIdByToolCallId: [String: String] = [:]
                            for call in calls {
                                let toolCallId = call.marker.payload["id"] ?? UUID().uuidString
                                let role = SubagentRole.fromToolName(call.name)
                                let subagentId = "\(role?.rawValue ?? call.name)-\(UUID().uuidString.prefix(8))"
                                subagentIdByToolCallId[toolCallId] = subagentId
                                continuation.yield(.raw(type: "agent", payload: [
                                    "title": role?.displayName ?? call.name,
                                    "detail": "started",
                                    "swarm_id": subagentId,
                                    "group_id": "swarm-\(subagentId)",
                                    "tool_call_id": toolCallId,
                                    "status": "started"
                                ]))
                            }

                            let capturedContext = context
                            let capturedSubagentIds = subagentIdByToolCallId
                            var anySubagentFailed = false
                            var completedRolesInBatch = Set<String>()

                            // Stream results as each subagent completes rather than
                            // collecting all results first — this keeps live cards
                            // updated incrementally.
                            await withTaskGroup(
                                of: (events: [StreamEvent], marker: CoderIDEMarker).self
                            ) { group in
                                for call in calls {
                                    let m = call.marker
                                    group.addTask { @Sendable in
                                        let produced = await self.events(
                                            for: m,
                                            context: capturedContext,
                                            preEmittedSubagentIds: capturedSubagentIds,
                                            onLiveSubagentEvent: { liveEvent in
                                                continuation.yield(liveEvent)
                                            }
                                        )
                                        return (events: produced, marker: m)
                                    }
                                }
                                for await result in group {
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
                                            completedRolesInBatch.insert(completedRole.rawValue.lowercased())
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
                                        // Events already streamed live via onLiveSubagentEvent
                                        // are not re-yielded to avoid duplicates.
                                        let alreadyEmitted: Bool = {
                                            if case .raw(_, let p) = e { return p["_live_emitted"] == "1" }
                                            return false
                                        }()
                                        if !alreadyEmitted {
                                            continuation.yield(e)
                                        }
                                    }
                                    if let summary = summarizeToolResultEvents(result.events, marker: result.marker) {
                                        roundToolResults.append(summary)
                                    }
                                }
                            }
                            let autoStatus = anySubagentFailed ? "blocked" : "done"
                            continuation.yield(.raw(type: "subagent_batch_done", payload: [
                                "status": autoStatus,
                                "count": "\(calls.count)",
                                "roles": completedRolesInBatch.sorted().joined(separator: ",")
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

                                // Pre-emit "started" events for injected subagents
                                var injectedSubagentIds: [String: String] = [:]
                                for call in injectedCalls {
                                    let toolCallId = call.marker.payload["id"] ?? UUID().uuidString
                                    let role = SubagentRole.fromToolName(call.name)
                                    let subagentId = "\(role?.rawValue ?? call.name)-\(UUID().uuidString.prefix(8))"
                                    injectedSubagentIds[toolCallId] = subagentId
                                    continuation.yield(.raw(type: "agent", payload: [
                                        "title": role?.displayName ?? call.name,
                                        "detail": "started",
                                        "swarm_id": subagentId,
                                        "group_id": "swarm-\(subagentId)",
                                        "tool_call_id": toolCallId,
                                        "status": "started"
                                    ]))
                                }

                                let capturedContext = context
                                let capturedInjectedIds = injectedSubagentIds

                                var injectedAnyFailed = false
                                var injectedCompletedRoles = Set<String>()
                                await withTaskGroup(
                                    of: (events: [StreamEvent], marker: CoderIDEMarker).self
                                ) { group in
                                    for call in injectedCalls {
                                        let marker = call.marker
                                        group.addTask { @Sendable in
                                            let produced = await self.events(
                                                for: marker,
                                                context: capturedContext,
                                                preEmittedSubagentIds: capturedInjectedIds,
                                                onLiveSubagentEvent: { liveEvent in
                                                    continuation.yield(liveEvent)
                                                }
                                            )
                                            return (events: produced, marker: marker)
                                        }
                                    }

                                    for await result in group {
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
                                                injectedCompletedRoles.insert(completedRole.rawValue.lowercased())
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
                                            let alreadyEmitted: Bool = {
                                                if case .raw(_, let p) = e { return p["_live_emitted"] == "1" }
                                                return false
                                            }()
                                            if !alreadyEmitted {
                                                continuation.yield(e)
                                            }
                                        }
                                        if let summary = summarizeToolResultEvents(result.events, marker: result.marker) {
                                            roundToolResults.append(summary)
                                        }
                                    }
                                }

                                continuation.yield(.raw(type: "subagent_batch_done", payload: [
                                    "status": injectedAnyFailed ? "blocked" : "done",
                                    "count": "\(injectedCalls.count)",
                                    "roles": injectedCompletedRoles.sorted().joined(separator: ",")
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
            continuation.onTermination = { _ in
                producerTask.cancel()
            }
        }
    }


}
