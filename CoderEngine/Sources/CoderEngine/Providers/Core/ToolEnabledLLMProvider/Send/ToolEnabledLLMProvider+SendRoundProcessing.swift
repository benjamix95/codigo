import Foundation

extension ToolEnabledLLMProvider {
    internal struct ToolRoundResult {
        let roundText: String
        let roundToolResults: [[String: String]]
        let pendingSubagentCalls: [(marker: CoderIDEMarker, name: String)]
        let sawExecutableSuggestion: Bool
        let didEmitMeaningfulText: Bool
        let sawCodeMutationDuringTask: Bool
        let reviewerCompletedAfterLatestMutation: Bool
        let testWriterCompletedAfterLatestMutation: Bool
        let mutatedPaths: Set<String>
        let acceptedSubagentInFirstRound: Bool
        let didEmitPolicyAck: Bool
    }

    internal func processToolRoundStream(
        stream: AsyncThrowingStream<StreamEvent, Error>,
        context: WorkspaceContext,
        isFirstRound: Bool,
        requiredPolicyHash: String?,
        enforceSubagentFirstRound: Bool,
        acceptedSubagentInFirstRound: Bool,
        didEmitPolicyAck: Bool,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws -> ToolRoundResult {
        var roundTextParts: [String] = []
        var roundTextLength = 0
        var roundToolResults: [[String: String]] = []
        var toolCallCountByKey: [String: Int] = [:]
        var toolCallsThisRound = 0
        var didEmitToolBudgetExceededThisRound = false
        var sawExecutableSuggestion = false
        var sawCodeMutationDuringTask = false
        var reviewerCompletedAfterLatestMutation = false
        var testWriterCompletedAfterLatestMutation = false
        var mutatedPaths: Set<String> = []
        var didEmitMeaningfulText = false
        var visibleTextLength = 0
        var didEmitPolicyAck = didEmitPolicyAck
        var localAcceptedSubagentInFirstRound = acceptedSubagentInFirstRound
        var pendingSubagentCalls: [(marker: CoderIDEMarker, name: String)] = []

        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                let visibleDelta = sanitizeVisibleDelta(delta)
                if !visibleDelta.isEmpty, roundTextLength + visibleDelta.count <= 100_000 {
                    roundTextParts.append(visibleDelta)
                    roundTextLength += visibleDelta.count
                }
                if !visibleDelta.isEmpty {
                    continuation.yield(.textDelta(visibleDelta))
                    // Track accumulated visible text length instead of checking
                    // per-delta, since individual deltas are small token fragments
                    // that would almost always fail the >= 24 char threshold.
                    visibleTextLength += visibleDelta.count
                    if visibleTextLength >= 24 {
                        didEmitMeaningfulText = true
                    }
                }

            case .textReplace(let replacement):
                let visibleReplacement = sanitizeVisibleDelta(replacement)
                roundTextParts = visibleReplacement.isEmpty ? [] : [visibleReplacement]
                roundTextLength = visibleReplacement.count
                continuation.yield(.textReplace(visibleReplacement))
                visibleTextLength = visibleReplacement.count
                if isMeaningfulAssistantCompletion(visibleReplacement) {
                    didEmitMeaningfulText = true
                }

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

                guard type == "tool_call_suggested" else {
                    continuation.yield(event)
                    continue
                }

                let isPartial = (payload["is_partial"] ?? "").lowercased() == "true"
                if isPartial { continue }
                let name = inferredToolName(from: payload)
                if name.isEmpty { continue }

                let exemptFromRoundBudget = UnifiedToolRuntime.readOnlyFileToolsExemptFromRoundBudget.contains(name)
                let exemptFromRepetitionLimit = UnifiedToolRuntime.readOnlyFileToolsExemptFromRepetitionLimit.contains(name)

                if !exemptFromRoundBudget, toolCallsThisRound >= policy.maxToolCallsPerRound {
                    if !didEmitToolBudgetExceededThisRound {
                        didEmitToolBudgetExceededThisRound = true
                        continuation.yield(.raw(type: "tool_execution_error", payload: [
                            "title": "Tool budget exceeded",
                            "detail": "Reached tool limit per round (\(policy.maxToolCallsPerRound))",
                            "status": "failed",
                            "error_code": "budget_exceeded"
                        ]))
                    }
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
                let resolvedSubagent = Self.resolveSubagentInvocation(
                    toolName: name,
                    payload: args
                )
                let effectiveMarker = resolvedSubagent.map {
                    Self.adaptedMarkerForResolvedSubagent(marker, resolved: $0)
                } ?? marker
                let effectiveName = resolvedSubagent?.toolName ?? name

                if enforceSubagentFirstRound,
                   !localAcceptedSubagentInFirstRound,
                   resolvedSubagent == nil,
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
                if !exemptFromRepetitionLimit, count >= policy.maxRepeatedSameToolPerRound {
                    continuation.yield(.raw(type: "tool_execution_error", payload: [
                        "title": "Repeated tool call dropped",
                        "detail": "Tool '\(name)' exceeded per-round repetition limit (\(policy.maxRepeatedSameToolPerRound)). Try a different approach.",
                        "status": "failed",
                        "error_code": "repeated_tool_limit",
                        "tool": name,
                    ]))
                    continue
                }
                toolCallCountByKey[dedupeId] = count + 1
                sawExecutableSuggestion = true

                if legacyInvokeSwarm || resolvedSubagent != nil {
                    localAcceptedSubagentInFirstRound = true
                }
                if let resolvedSubagent {
                    pendingSubagentCalls.append((marker: effectiveMarker, name: effectiveName))
                    let toolCallId = effectiveMarker.payload["id"] ?? UUID().uuidString
                    let queuedIdentity = SubagentExecutionIdentityBuilder.make(
                        role: resolvedSubagent.role,
                        task: effectiveMarker.payload["task"] ?? effectiveMarker.payload["prompt"] ?? ""
                    )
                    continuation.yield(.raw(type: "agent", payload: [
                        "title": queuedIdentity.agentName,
                        "detail": "queued",
                        "swarm_id": "queued-\(toolCallId)",
                        "tool_call_id": toolCallId,
                        "status": "queued"
                    ]))
                } else {
                    if !exemptFromRoundBudget {
                        toolCallsThisRound += 1
                    }
                    let produced = await events(for: effectiveMarker, context: context)
                    for e in produced {
                        if Self.streamEventIndicatesCodeMutation(e, originatingToolName: name) {
                            sawCodeMutationDuringTask = true
                            reviewerCompletedAfterLatestMutation = false
                            testWriterCompletedAfterLatestMutation = false
                            if let path = Self.mutatedFilePath(from: e, originatingToolName: name) {
                                mutatedPaths.insert(path)
                            }
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
            }
        }

        return ToolRoundResult(
            roundText: roundTextParts.joined(),
            roundToolResults: roundToolResults,
            pendingSubagentCalls: pendingSubagentCalls,
            sawExecutableSuggestion: sawExecutableSuggestion,
            didEmitMeaningfulText: didEmitMeaningfulText,
            sawCodeMutationDuringTask: sawCodeMutationDuringTask,
            reviewerCompletedAfterLatestMutation: reviewerCompletedAfterLatestMutation,
            testWriterCompletedAfterLatestMutation: testWriterCompletedAfterLatestMutation,
            mutatedPaths: mutatedPaths,
            acceptedSubagentInFirstRound: localAcceptedSubagentInFirstRound,
            didEmitPolicyAck: didEmitPolicyAck
        )
    }
}
