import Foundation

extension ToolEnabledLLMProvider {
    internal struct SubagentBatchResult {
        let roundToolResults: [[String: String]]
        let sawCodeMutationDuringTask: Bool
        let reviewerCompletedAfterLatestMutation: Bool
        let testWriterCompletedAfterLatestMutation: Bool
        let mutatedPaths: Set<String>
        let didEmitPolicyAck: Bool
        let anyFailed: Bool
    }

    internal func executeSubagentCallBatch(
        calls: [(marker: CoderIDEMarker, name: String)],
        context: WorkspaceContext,
        requiredPolicyHash: String?,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        emitStartedEvents: Bool = true
    ) async -> SubagentBatchResult {
        guard !calls.isEmpty else {
            return SubagentBatchResult(
                roundToolResults: [],
                sawCodeMutationDuringTask: false,
                reviewerCompletedAfterLatestMutation: false,
                testWriterCompletedAfterLatestMutation: false,
                mutatedPaths: [],
                didEmitPolicyAck: false,
                anyFailed: false
            )
        }

        var roundToolResults: [[String: String]] = []
        var batchHadMutation = false
        var batchHadReviewerCompletion = false
        var batchHadTestWriterCompletion = false
        var mutatedPaths: Set<String> = []
        var didEmitPolicyAck = false
        var anyFailed = false
        var completedRolesInBatch = Set<String>()

        var subagentIdentityByCallId: [String: SubagentExecutionIdentity] = [:]
        var identityCountsByBaseName: [String: Int] = [:]
        if emitStartedEvents {
            for call in calls {
                let toolCallId = call.marker.payload["id"] ?? UUID().uuidString
                let role = SubagentRole.fromToolName(call.name)
                let task = call.marker.payload["task"] ?? call.marker.payload["prompt"] ?? ""
                let identity: SubagentExecutionIdentity
                if let role {
                    let baseName = SubagentExecutionIdentityBuilder.baseName(role: role, task: task)
                    let nextCount = (identityCountsByBaseName[baseName] ?? 0) + 1
                    identityCountsByBaseName[baseName] = nextCount
                    identity = SubagentExecutionIdentityBuilder.make(
                        role: role,
                        task: task,
                        collisionIndex: nextCount > 1 ? nextCount : nil
                    )
                } else {
                    identity = SubagentExecutionIdentity(
                        swarmId: toolCallId,
                        agentName: call.name,
                        taskSummary: SubagentExecutionIdentityBuilder.taskSummary(from: task)
                    )
                }
                subagentIdentityByCallId[toolCallId] = identity
                continuation.yield(.raw(type: "agent", payload: [
                    "title": identity.agentName,
                    "detail": "queued",
                    "swarm_id": "queued-\(toolCallId)",
                    "group_id": "swarm-queued-\(toolCallId)",
                    "agent_name": identity.agentName,
                    "tool_call_id": toolCallId,
                    "status": "queued"
                ]))
            }
        }
        let capturedContext = context
        let capturedIdentities = subagentIdentityByCallId

        await withTaskGroup(of: (events: [StreamEvent], marker: CoderIDEMarker).self) { group in
            for call in calls {
                let marker = call.marker
                group.addTask { @Sendable in
                    let produced = await self.events(
                        for: marker,
                        context: capturedContext,
                        preAssignedSubagentIdentities: capturedIdentities,
                        onLiveSubagentEvent: { liveEvent in
                            if case .raw(let type, let payload) = liveEvent {
                                SubagentPipelineLogger.log(
                                    "parent_receive_live type=\(type) swarm=\(payload["swarm_id"] ?? "-") stage=\(payload["subagent_stage"] ?? "-") detail=\(payload["detail"] ?? "-")"
                                )
                            }
                            continuation.yield(liveEvent)
                        }
                    )
                    return (events: produced, marker: marker)
                }
            }

            for await result in group {
                let subagentToolName = result.marker.payload["name"] ?? result.marker.payload["tool"] ?? ""
                for e in result.events {
                    if Self.streamEventIndicatesCodeMutation(e, originatingToolName: subagentToolName) {
                        batchHadMutation = true
                        if let path = Self.mutatedFilePath(from: e, originatingToolName: subagentToolName) {
                            mutatedPaths.insert(path)
                        }
                    }
                    if let completedRole = Self.completedSubagentRole(from: e) {
                        completedRolesInBatch.insert(completedRole.rawValue.lowercased())
                        if completedRole == .reviewer {
                            batchHadReviewerCompletion = true
                        }
                        if completedRole == .testWriter {
                            batchHadTestWriterCompletion = true
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
                    if case .raw(let type, let payload) = e,
                       type == "tool_result",
                       payload["status"] == "failed" {
                        anyFailed = true
                    }
                    let alreadyEmitted: Bool = {
                        if case .raw(_, let payload) = e { return payload["_live_emitted"] == "1" }
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
            "status": anyFailed ? "blocked" : "done",
            "count": "\(calls.count)",
            "roles": completedRolesInBatch.sorted().joined(separator: ",")
        ]))

        // Resolve batch states: if mutations happened in a parallel batch,
        // reviewer/testWriter completions from the SAME batch are stale
        // (they reviewed pre-mutation code since they ran concurrently).
        let resolvedReviewerCompleted: Bool
        let resolvedTestWriterCompleted: Bool
        if batchHadMutation {
            resolvedReviewerCompleted = false
            resolvedTestWriterCompleted = false
        } else {
            resolvedReviewerCompleted = batchHadReviewerCompletion
            resolvedTestWriterCompleted = batchHadTestWriterCompletion
        }

        return SubagentBatchResult(
            roundToolResults: roundToolResults,
            sawCodeMutationDuringTask: batchHadMutation,
            reviewerCompletedAfterLatestMutation: resolvedReviewerCompleted,
            testWriterCompletedAfterLatestMutation: resolvedTestWriterCompleted,
            mutatedPaths: mutatedPaths,
            didEmitPolicyAck: didEmitPolicyAck,
            anyFailed: anyFailed
        )
    }

    internal func emitForcedFinalization(
        prompt: String,
        context: WorkspaceContext,
        transcript: String,
        toolResults: [[String: String]],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async -> Bool {
        let forcedPrompt = buildForcedFinalizationPrompt(
            originalPrompt: prompt,
            transcript: transcript,
            toolResults: toolResults
        )

        var forcedTextParts: [String] = []
        var forcedTextLength = 0

        do {
            let forcedStream = try await base.send(
                prompt: forcedPrompt,
                context: context,
                imageURLs: nil
            )
            for try await forcedEvent in forcedStream {
                switch forcedEvent {
                case .textDelta(let delta):
                    let visible = sanitizeVisibleDelta(delta)
                    if !visible.isEmpty {
                        continuation.yield(.textDelta(visible))
                        if forcedTextLength + visible.count <= 50_000 {
                            forcedTextParts.append(visible)
                            forcedTextLength += visible.count
                        }
                    }
                case .textReplace(let replacement):
                    let visible = sanitizeVisibleDelta(replacement)
                    continuation.yield(.textReplace(visible))
                    forcedTextParts = visible.isEmpty ? [] : [visible]
                    forcedTextLength = visible.count
                default:
                    break
                }
            }
            let hasMeaningful = isMeaningfulAssistantCompletion(forcedTextParts.joined())
            if !hasMeaningful {
                continuation.yield(.raw(type: "tool_execution_error", payload: [
                    "title": "Missing final outcome",
                    "detail": "Provider finished without final summary after tool execution",
                    "status": "failed",
                    "error_code": "missing_final_outcome"
                ]))
                let fallback = buildToolFallbackSummary(toolResults)
                if !fallback.isEmpty {
                    continuation.yield(.textDelta(fallback))
                }
            }
            return hasMeaningful
        } catch {
            continuation.yield(.raw(type: "tool_execution_error", payload: [
                "title": "Finalization failed",
                "detail": error.localizedDescription,
                "status": "failed",
                "error_code": "missing_final_outcome"
            ]))
            let fallback = buildToolFallbackSummary(toolResults)
            if !fallback.isEmpty {
                continuation.yield(.textDelta(fallback))
            }
            // Return false instead of re-throwing to let the caller continue
            // with post-finalization checks (mandatory review warnings, etc.)
            return false
        }
    }

    internal func buildAutoInjectedReviewCalls(
        sawReviewerComplete: Bool,
        sawTestWriterComplete: Bool,
        modifiedPaths: Set<String>
    ) -> [(marker: CoderIDEMarker, name: String)] {
        var injectedCalls: [(marker: CoderIDEMarker, name: String)] = []
        let changedFilesHint = autoInjectedChangedFilesHint(modifiedPaths)
        if !sawReviewerComplete {
            injectedCalls.append((
                marker: CoderIDEMarker(kind: "tool_call", payload: [
                    "id": "auto-reviewer-\(UUID().uuidString)",
                    "name": SubagentRole.reviewer.toolName,
                    "task": "\(changedFilesHint) Review all code changes completed in this task. Report bugs, regressions, and risks with concrete findings.",
                ]),
                name: SubagentRole.reviewer.toolName
            ))
        }
        if !sawTestWriterComplete {
            injectedCalls.append((
                marker: CoderIDEMarker(kind: "tool_call", payload: [
                    "id": "auto-testwriter-\(UUID().uuidString)",
                    "name": SubagentRole.testWriter.toolName,
                    "task": "\(changedFilesHint) Write and run focused regression tests for all code changes completed in this task. Report failures and coverage gaps.",
                ]),
                name: SubagentRole.testWriter.toolName
            ))
        }
        return injectedCalls
    }

    private func autoInjectedChangedFilesHint(_ modifiedPaths: Set<String>) -> String {
        guard !modifiedPaths.isEmpty else {
            return "Code mutations were detected."
        }
        let sorted = modifiedPaths.sorted()
        let preview = sorted.prefix(20).joined(separator: ", ")
        if sorted.count > 20 {
            return "Code mutations were detected in files (partial): \(preview), +\(sorted.count - 20) more."
        }
        return "Code mutations were detected in files: \(preview)."
    }
}
