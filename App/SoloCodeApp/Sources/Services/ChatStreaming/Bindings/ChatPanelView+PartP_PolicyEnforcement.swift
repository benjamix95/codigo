import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func shouldBypassPolicyAckLiveVisibilityGate(
    type rawType: String,
    payload: [String: String]
) -> Bool {
    let type = rawType
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let directTypes: Set<String> = [
        "assistant_update",
        "agent",
        "subagent_text",
        "bash",
        "command_execution",
        "file_change",
        "edit",
        "search",
        "semantic_search",
        "instant_grep",
        "mcp_tool_call",
        "skill_invocation",
        "permission_denied",
        "tool_execution_error",
        "tool_timeout",
        "tool_validation_error",
        "error",
    ]
    if directTypes.contains(type) { return true }
    if ["web_search", "web_fetch", "read_batch", "debug_", "plan_"].contains(where: type.hasPrefix) {
        return true
    }
    return payload["swarm_id"] != nil && (type == "agent" || type == "subagent_text")
}

extension ChatPanelView {
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
            state.violationEmitted = false
            policyAckFailedMessages.remove(turn.assistantMessageId)
            enriched["status"] = "acknowledged"
            enriched["title"] = payload["title"] ?? "Policy acknowledged"
            enriched["detail"] = payload["detail"] ?? "Policy hash accepted"
        } else {
            policyAckFailedMessages.insert(turn.assistantMessageId)
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
        if isSwarmPolicyAckExemptProvider(providerId) {
            return false
        }
        if shouldBypassPolicyAckLiveVisibilityGate(type: type, payload: payload) {
            return false
        }
        guard ToolTraceVisibility.requiresPolicyAck(type: type, payload: payload) else { return false }
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return false
        }
        guard var state = policyAckStateByMessage[turn.assistantMessageId] else {
            return false
        }
        if state.isSatisfied { return false }
        if state.violationEmitted { return true }

        // Hold operational events until the required policy_ack arrives.
        // ToolEnabledLLMProvider emits the ack synthetically, so this path mostly
        // protects against event reordering instead of representing a hard failure.
        state.violationEmitted = true
        policyAckStateByMessage[turn.assistantMessageId] = state
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
        guard policyAckStateByMessage[turn.assistantMessageId]?.isSatisfied == true else {
            return
        }
        let messageId = turn.assistantMessageId
        guard let queued = policyAckBlockedQueue.removeValue(forKey: messageId), !queued.isEmpty else {
            return
        }
        for event in queued {
            handleRawStreamEvent(
                type: event.type,
                payload: event.payload,
                providerId: event.providerId,
                conversationId: event.conversationId,
                shouldApplyPipelineArtifacts: event.shouldApplyPipelineArtifacts
            )
        }
    }

    @MainActor
    internal func stopTaskForPolicyViolation(conversationId: UUID?) {
        let didCancelPipeline = pipelineIntegrationService.cancelCurrentJob(for: conversationId)
        var didCancelTask = didCancelPipeline || cancelRunTask(for: conversationId)
        if !didCancelTask, let target = conversationId,
           activeBuildPlanConversationId == target,
           let agentId = activeBuildAgentConversationId {
            didCancelTask =
                pipelineIntegrationService.cancelCurrentJob(for: agentId)
                || cancelRunTask(for: agentId)
        }
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
