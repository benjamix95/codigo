import Foundation

extension ToolEnabledLLMProvider {
    internal struct SubagentBatchResult {
        let roundToolResults: [[String: String]]
        let sawCodeMutationDuringTask: Bool
        let reviewerCompletedAfterLatestMutation: Bool
        let testWriterCompletedAfterLatestMutation: Bool
        let didEmitPolicyAck: Bool
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
                didEmitPolicyAck: false
            )
        }

        var roundToolResults: [[String: String]] = []
        var sawCodeMutationDuringTask = false
        var reviewerCompletedAfterLatestMutation = false
        var testWriterCompletedAfterLatestMutation = false
        var didEmitPolicyAck = false
        var anyFailed = false
        var completedRolesInBatch = Set<String>()

        var subagentIdByCallId: [String: String] = [:]
        if emitStartedEvents {
            for call in calls {
                let toolCallId = call.marker.payload["id"] ?? UUID().uuidString
                let role = SubagentRole.fromToolName(call.name)
                let subagentId = "\(role?.rawValue ?? call.name)-\(UUID().uuidString.prefix(8))"
                subagentIdByCallId[toolCallId] = subagentId
                continuation.yield(.raw(type: "agent", payload: [
                    "title": role?.displayName ?? call.name,
                    "detail": "started",
                    "swarm_id": subagentId,
                    "group_id": "swarm-\(subagentId)",
                    "tool_call_id": toolCallId,
                    "status": "started"
                ]))
            }
        }
        let capturedContext = context
        let capturedSubagentIds = subagentIdByCallId

        await withTaskGroup(of: (events: [StreamEvent], marker: CoderIDEMarker).self) { group in
            for call in calls {
                let marker = call.marker
                group.addTask { @Sendable in
                    let produced = await self.events(
                        for: marker,
                        context: capturedContext,
                        preEmittedSubagentIds: capturedSubagentIds,
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
                    if Self.streamEventIndicatesCodeMutation(e, originatingToolName: subagentToolName) {
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

        return SubagentBatchResult(
            roundToolResults: roundToolResults,
            sawCodeMutationDuringTask: sawCodeMutationDuringTask,
            reviewerCompletedAfterLatestMutation: reviewerCompletedAfterLatestMutation,
            testWriterCompletedAfterLatestMutation: testWriterCompletedAfterLatestMutation,
            didEmitPolicyAck: didEmitPolicyAck
        )
    }

    internal func emitForcedFinalization(
        prompt: String,
        context: WorkspaceContext,
        transcript: String,
        toolResults: [[String: String]],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws -> Bool {
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
            throw error
        }
    }

    internal func buildAutoInjectedReviewCalls(
        sawReviewerComplete: Bool,
        sawTestWriterComplete: Bool
    ) -> [(marker: CoderIDEMarker, name: String)] {
        var injectedCalls: [(marker: CoderIDEMarker, name: String)] = []
        if !sawReviewerComplete {
            injectedCalls.append((
                marker: CoderIDEMarker(kind: "tool_call", payload: [
                    "id": "auto-reviewer-\(UUID().uuidString)",
                    "name": SubagentRole.reviewer.toolName,
                    "task": "Review all code changes completed in this task. Report bugs, regressions, and risks with concrete findings.",
                ]),
                name: SubagentRole.reviewer.toolName
            ))
        }
        if !sawTestWriterComplete {
            injectedCalls.append((
                marker: CoderIDEMarker(kind: "tool_call", payload: [
                    "id": "auto-testwriter-\(UUID().uuidString)",
                    "name": SubagentRole.testWriter.toolName,
                    "task": "Write and run focused regression tests for all code changes completed in this task. Report failures and coverage gaps.",
                ]),
                name: SubagentRole.testWriter.toolName
            ))
        }
        return injectedCalls
    }
}
