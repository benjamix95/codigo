import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func handleRawStreamEvent(
        type t: String, payload p: [String: String], providerId pid: String,
        conversationId convId: UUID?
    ) {
        if t == "policy_ack" {
            let enriched = processPolicyAckEvent(payload: p, providerId: pid, conversationId: convId)
            recordTaskActivity(type: t, payload: enriched, providerId: pid, conversationId: convId)
            flushPolicyAckBlockedQueue(providerId: pid, conversationId: convId)
            return
        }
        if shouldHardBlockForMissingPolicyAck(
            type: t,
            payload: p,
            providerId: pid,
            conversationId: convId
        ) {
            // Queue the event instead of silently dropping it.
            // It will be flushed when the policy_ack arrives.
            if let turn = resolveToolTraceTurn(conversationId: convId, providerId: pid) {
                if !policyAckFailedMessages.contains(turn.assistantMessageId) {
                    policyAckBlockedQueue[turn.assistantMessageId, default: []].append(
                        (type: t, payload: p, providerId: pid, conversationId: convId)
                    )
                }
            }
            return
        }
        if t == "tool_validation_error",
           isMCPEditRequiredViolation(payload: p) {
            var enriched = p
            enriched["status"] = "failed"
            if (enriched["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                enriched["title"] = "MCP-only editing policy violation"
            }
            if (enriched["detail"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                enriched["detail"] = "Edit requests must use the coderide MCP tools."
            }
            recordTaskActivity(type: t, payload: enriched, providerId: pid, conversationId: convId)
            emitMCPEditRequiredViolation(payload: enriched, conversationId: convId)
            return
        }
        if t == "turn_started" {
            streamingSegmentTurnIndex += 1
            resetReasoningMessageState(for: convId)
            if shouldUseLinearChat(providerId: pid) {
                splitStreamingMessageForNewTurn(conversationId: convId, providerId: pid)
            }
        }
        if t == "reasoning", let output = p["output"], !output.isEmpty {
            if shouldUseLinearChat(providerId: pid) {
                // For Codex linear chat, reasoning is shown only as streaming
                // status/detail text, never as an inline thinking box.
                if convId == self.conversationId {
                    codexLastReasoningLine = output.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if shouldSplitThinkingMessages(providerId: pid) {
                let groupId = p["group_id"] ?? "reasoning-stream"
                upsertSeparateThinkingMessage(
                    output: output,
                    groupId: groupId,
                    conversationId: convId
                )
                if convId == self.conversationId {
                    streamingReasoningText = nil
                    streamingReasoningConversationId = nil
                    streamingReasoningBlocks = []
                    streamingSegments.removeAll { segment in
                        if case .reasoning = segment.kind {
                            return true
                        }
                        return false
                    }
                }
            } else {
                let groupId = p["group_id"] ?? "reasoning-stream"
                if streamingReasoningConversationId != convId {
                    streamingReasoningBlocks = []
                    streamingSegments = []
                    streamingSegmentTurnIndex = 0
                }
                if let idx = streamingReasoningBlocks.firstIndex(where: { $0.id == groupId }) {
                    streamingReasoningBlocks[idx].text = Self.mergeReasoningText(
                        existing: streamingReasoningBlocks[idx].text,
                        incoming: output
                    )
                } else {
                    streamingReasoningBlocks.append(ReasoningBlock(id: groupId, text: output))
                }
                streamingReasoningText = streamingReasoningBlocks.map(\.text).joined(separator: "\n\n")
                streamingReasoningConversationId = convId

                if sequentialStreamingLayoutEnabled {
                    let segId = "reasoning-\(streamingSegmentTurnIndex)"
                    let currentBlockText = streamingReasoningBlocks.last(where: { $0.id == groupId })?.text ?? output
                    if let segIdx = streamingSegments.firstIndex(where: { $0.id == segId }) {
                        streamingSegments[segIdx].kind = .reasoning(currentBlockText)
                    } else {
                        streamingSegments.append(MessageSegment(id: segId, kind: .reasoning(currentBlockText)))
                    }
                }
            }
        }
        if t == "coderide_show_task_panel" { enableTaskPanelIfNeeded() }
        if t == "coderide_show_swarm_panel",
           planFlowPhase != .building,
           shouldAutoOpenSwarmPanelForEvent(
               eventConversationId: convId,
               selectedConversationId: selectedConversationId
           )
        {
            showSwarmPanel = true
            if let swarmId = SwarmMetadata.swarmId(from: p) {
                selectedSwarmId = swarmId
            }
        }
        if t == "swarm_steps", let s = p["steps"], !s.isEmpty {
            let n = s.split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            swarmProgressStore.setSteps(n)
        }
        if t == "agent", let title = p["title"], let detail = p["detail"] {
            if detail == "started" {
                swarmProgressStore.markStarted(name: title)
            } else if detail == "completed" {
                swarmProgressStore.markCompleted(name: title)
            }
        }
        if t == "usage",
           let inpStr = p["input_tokens"], let outStr = p["output_tokens"],
           let inp = Int(inpStr), let out = Int(outStr) {
            if pid.hasSuffix("-api") {
                providerUsageStore.addApiUsage(
                    inputTokens: inp,
                    outputTokens: out,
                    model: p["model"] ?? "gpt-4o-mini"
                )
            } else if pid == "claude-cli" {
                let current = providerUsageStore.claudeUsage
                let merged = ClaudeUsage(
                    sessionCost: current?.sessionCost,
                    inputTokens: max(current?.inputTokens ?? 0, inp),
                    outputTokens: max(current?.outputTokens ?? 0, out),
                    cacheReadTokens: current?.cacheReadTokens,
                    cacheWriteTokens: current?.cacheWriteTokens,
                    totalDuration: current?.totalDuration
                )
                providerUsageStore.claudeUsage = merged
                providerUsageStore.claudeUsageMessage = nil
            }
            let prev = chatStore.conversation(for: convId)?.lastInputTokens ?? 0
            if inp > prev {
                chatStore.updateLastInputTokens(inp, for: convId)
            }
        }
        if t == "subagent_batch_done" {
            autoCompleteInProgressTodoAfterSubagents(
                status: p["status"] ?? "done",
                payload: p,
                conversationId: convId
            )
            return // Don't record this synthetic event as a visible activity
        }
        recordTaskActivity(type: t, payload: p, providerId: pid, conversationId: convId)
    }

    @MainActor
    internal func autoCompleteInProgressTodoAfterSubagents(
        status: String,
        payload: [String: String],
        conversationId: UUID?
    ) {
        let normalizedStatus = status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let targetStatus: TodoStatus = normalizedStatus == "done" ? .done : .blocked
        let targetIDs = todoIDsToAutoCompleteAfterSubagentBatch(
            todos: todoStore.todos,
            conversationId: conversationId,
            includePendingReviewTodo: shouldAutoCompletePendingReviewTodo(
                subagentBatchPayload: payload
            )
        )
        for id in targetIDs {
            todoStore.setStatus(id: id, status: targetStatus)
        }
    }

    @MainActor
    internal func processPolicyAckEvent(
        payload: [String: String],
        providerId: String,
        conversationId: UUID?
    ) -> [String: String] {
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return payload
        }
        guard var state = policyAckStateByMessage[turn.assistantMessageId] else {
            return payload
        }

        let receivedHash = (payload["hash"] ?? payload["policy_hash"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var enriched = payload
        enriched["expected_hash"] = state.expectedHash

        if receivedHash == state.expectedHash {
            state.acknowledgedHash = receivedHash
            policyAckFailedMessages.remove(turn.assistantMessageId)
            enriched["status"] = "acknowledged"
            enriched["title"] = payload["title"] ?? "Policy acknowledged"
            enriched["detail"] = payload["detail"] ?? "Policy hash accepted"
        } else {
            enriched["status"] = "invalid"
            enriched["title"] = payload["title"] ?? "Policy acknowledgment invalid"
            enriched["detail"] = payload["detail"] ?? "Expected hash \(state.expectedHash)"
        }
        policyAckStateByMessage[turn.assistantMessageId] = state
        return enriched
    }

    @MainActor
    internal func shouldHardBlockForMissingPolicyAck(
        type: String,
        payload: [String: String],
        providerId: String,
        conversationId: UUID?
    ) -> Bool {
        guard agentsHardBlockEnabled else { return false }
        if isSwarmPolicyAckExemptProvider(providerId) || hasSwarmTraceMetadata(payload) {
            return false
        }
        guard ToolTraceVisibility.requiresPolicyAck(type: type, payload: payload) else { return false }
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return false
        }
        if policyAckFailedMessages.contains(turn.assistantMessageId) {
            return true
        }
        guard var state = policyAckStateByMessage[turn.assistantMessageId] else {
            return false
        }
        if state.isSatisfied { return false }
        if state.violationEmitted { return true }

        state.violationEmitted = true
        policyAckStateByMessage[turn.assistantMessageId] = state
        policyAckFailedMessages.insert(turn.assistantMessageId)
        policyAckBlockedQueue.removeValue(forKey: turn.assistantMessageId)
        emitPolicyAckViolation(
            expectedHash: state.expectedHash,
            incomingType: type,
            providerId: providerId,
            conversationId: conversationId
        )
        return true
    }

    @MainActor
    internal func isSwarmPolicyAckExemptProvider(_ providerId: String) -> Bool {
        let normalized = providerId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.isEmpty { return false }
        return normalized == "swarm-runtime-internal"
            || normalized == "code-review-multi-swarm"
            || normalized.hasPrefix("swarm-")
            || normalized.contains("multi-swarm")
    }

    @MainActor
    internal func hasSwarmTraceMetadata(_ payload: [String: String]) -> Bool {
        return SwarmMetadata.isSwarmEvent(payload)
    }

    @MainActor
    internal func routeDebugEvent(
        _ event: NormalizedEvent,
        payload: [String: String],
        eventConversationId: UUID?
    ) {
        if shouldHandleDebugStoreEvent(payload: payload, eventConversationId: eventConversationId) {
            applyDebugEventToActiveStore(event)
            persistDebugState(for: selectedConversationId)
            return
        }
        guard !SwarmMetadata.isSwarmEvent(payload), let eventConversationId else {
            return
        }
        pendingDebugEventsByConversation[eventConversationId, default: []].append(event)
    }

    @MainActor
    internal func applyDebugEventToActiveStore(_ event: NormalizedEvent) {
        switch event {
        case .debugPhaseUpdate(let phase, let detail):
            handleDebugPhaseUpdate(phase: phase, detail: detail)
        case .debugUserRequest(let kind, let prompt):
            handleDebugUserRequest(kind: kind, prompt: prompt)
        case .debugResolved(let summary):
            handleDebugResolved(summary: summary)
        case .debugLog(let payload):
            handleDebugLogPayload(payload)
        case .debugHypothesize(let payload):
            handleDebugHypothesizePayload(payload)
        case .debugMark(let payload):
            handleDebugMarkPayload(payload)
        case .debugInstrument(let payload):
            handleDebugInstrumentPayload(payload)
        case .debugClean(let payload):
            handleDebugCleanPayload(payload)
        case .debugSession(let payload):
            handleDebugSessionPayload(payload)
        case .debugQuery(let payload):
            handleDebugQueryPayload(payload)
        default:
            break
        }
    }

    @MainActor
    internal func persistDebugState(for conversationId: UUID?) {
        guard let conversationId else { return }
        debugStateByConversation[conversationId] = debugStore.snapshot()
    }

    @MainActor
    internal func restoreDebugState(for conversationId: UUID?) {
        guard let conversationId else {
            debugStore.resetSession()
            return
        }
        if let snapshot = debugStateByConversation[conversationId] {
            debugStore.restore(from: snapshot)
        } else {
            debugStore.resetSession()
        }
    }

    @MainActor
    internal func applyPendingDebugEvents(for conversationId: UUID?) {
        guard let conversationId,
              let pending = pendingDebugEventsByConversation.removeValue(forKey: conversationId),
              !pending.isEmpty
        else {
            return
        }
        for event in pending {
            applyDebugEventToActiveStore(event)
        }
        persistDebugState(for: conversationId)
    }

    @MainActor
    internal func shouldHandleDebugStoreEvent(payload: [String: String], eventConversationId: UUID?) -> Bool {
        if SwarmMetadata.isSwarmEvent(payload) {
            return false
        }
        guard let selectedConversationId else {
            return false
        }
        guard let eventConversationId else {
            return true
        }
        return eventConversationId == selectedConversationId
    }

    @MainActor
    internal func emitPolicyAckViolation(
        expectedHash: String,
        incomingType: String,
        providerId: String,
        conversationId: UUID?
    ) {
        let detail =
            "Missing required marker [CODERIDE:policy_ack|hash=\(expectedHash)] before event '\(incomingType)'."
        recordTaskActivity(
            type: "tool_execution_error",
            payload: [
                "title": "Policy acknowledgment required",
                "detail": detail,
                "status": "failed",
                "error_code": "policy_ack_missing",
                "expected_hash": expectedHash,
            ],
            providerId: providerId,
            conversationId: conversationId
        )
        appendTechnicalErrorMessage(
            "[Policy error] Mandatory AGENTS/SKILL acknowledgment missing. Emit [CODERIDE:policy_ack|hash=\(expectedHash)] before using tools.",
            in: conversationId
        )
        stopTaskForPolicyViolation(conversationId: conversationId)
    }

    @MainActor
    internal func isMCPEditRequiredViolation(payload: [String: String]) -> Bool {
        let code = (payload["error_code"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return code == "mcp_edit_required"
    }

    @MainActor
    internal func emitMCPEditRequiredViolation(payload: [String: String], conversationId: UUID?) {
        let detail = (payload["detail"] ?? "Edit requests must use the coderide MCP tools.")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        appendTechnicalErrorMessage(
            "[Policy error] \(detail)",
            in: conversationId
        )
        stopTaskForPolicyViolation(conversationId: conversationId)
    }

    /// Flush events that were queued while waiting for policy_ack.
    @MainActor
    internal func flushPolicyAckBlockedQueue(providerId: String, conversationId: UUID?) {
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }
        let messageId = turn.assistantMessageId
        guard let queued = policyAckBlockedQueue.removeValue(forKey: messageId), !queued.isEmpty else {
            return
        }
        for event in queued {
            recordTaskActivity(
                type: event.type,
                payload: event.payload,
                providerId: event.providerId,
                conversationId: event.conversationId
            )
        }
    }

    @MainActor
    internal func stopTaskForPolicyViolation(conversationId: UUID?) {
        let didCancelTask = cancelRunTask(for: conversationId)
        if !didCancelTask {
            let scope = executionScopeForActiveTask()
            executionController.terminate(scope: scope)
        }
        applyFlowCoordinatorState(for: conversationId) { $0.interrupt() }
        taskFlushTask?.cancel()
        taskFlushTask = nil
        flushPendingTaskActivities()
        if let conversationId {
            chatStore.setLastAssistantStreaming(false, in: conversationId)
            clearStreamingReasoning(for: conversationId)
        }
        finalizeToolTraceTurn(conversationId: conversationId, outcome: .failed)
        if conversationId == self.conversationId {
            cancelFallbackTurnStartEvent()
        }
        snapshotSubagentCardsAndEndTask(conversationId: conversationId)
        if conversationId == self.conversationId
            || activeBuildAgentConversationId == conversationId {
            activeBuildPlanConversationId = nil
            activeBuildAgentConversationId = nil
            resetPlanFlowAfterInterruption()
        }
    }

}
