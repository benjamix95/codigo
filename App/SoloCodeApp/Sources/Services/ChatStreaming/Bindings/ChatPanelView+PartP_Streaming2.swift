import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func handleRawStreamEvent(
        type t: String, payload p: [String: String], providerId pid: String,
        conversationId convId: UUID?,
        shouldApplyPipelineArtifacts: Bool = true,
        shouldUpdateInlineReasoningVisuals: Bool = true
    ) {
        if t == "assistant_update"
            || t == "turn_started"
            || t == "turn_completed"
            || t == "command_execution"
            || t == "mcp_tool_call"
        {
            mainChatTraceLog(
                "raw type=\(t) provider=\(pid) conv=\(convId?.uuidString.lowercased() ?? "-") title=\(p["title"] ?? "-") detail=\(p["detail"] ?? "-") status=\(p["status"] ?? "-")"
            )
        }
        if let ackPayload = policyAckPayloadFromEvent(type: t, payload: p) {
            let enriched = processPolicyAckEvent(payload: ackPayload, providerId: pid, conversationId: convId)
            recordTaskActivity(type: "policy_ack", payload: enriched, providerId: pid, conversationId: convId)
            if policyAckDisposition(status: enriched["status"]) == .acknowledged {
                flushPolicyAckBlockedQueue(providerId: pid, conversationId: convId)
            }
        }
        if t == "policy_ack" {
            let enriched = processPolicyAckEvent(payload: p, providerId: pid, conversationId: convId)
            recordTaskActivity(type: t, payload: enriched, providerId: pid, conversationId: convId)
            switch policyAckDisposition(status: enriched["status"]) {
            case .acknowledged:
                flushPolicyAckBlockedQueue(providerId: pid, conversationId: convId)
            case .invalid:
                appendTechnicalErrorMessage(
                    "[Policy error] Invalid AGENTS/SKILL acknowledgment received. Expected hash \(enriched["expected_hash"] ?? "?").",
                    in: convId
                )
                stopTaskForPolicyViolation(
                    conversationId: convId,
                    reason: "policy_ack_raw_invalid"
                )
            case .ignored:
                break
            }
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
                toolRuntime.policyAckBlockedQueue[turn.assistantMessageId, default: []].append(
                    (
                        type: t,
                        payload: p,
                        providerId: pid,
                        conversationId: convId,
                        shouldApplyPipelineArtifacts: shouldApplyPipelineArtifacts
                    )
                )
            }
            return
        }
        updateToolStartRequirementsStateIfNeeded(
            type: t,
            payload: p,
            providerId: pid,
            conversationId: convId
        )
        if shouldHardBlockForMissingTodoOrPlan(
            type: t,
            payload: p,
            providerId: pid,
            conversationId: convId
        ) {
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
        handleRawStreamEventContinuation(
            type: t,
            payload: p,
            providerId: pid,
            conversationId: convId,
            shouldApplyPipelineArtifacts: shouldApplyPipelineArtifacts,
            shouldUpdateInlineReasoningVisuals: shouldUpdateInlineReasoningVisuals
        )
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
        let excludeCanonicalTodos = isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
        let targetIDs = todoIDsToAutoCompleteAfterSubagentBatch(
            todos: todoStore.todos,
            conversationId: conversationId,
            includePendingReviewTodo: shouldAutoCompletePendingReviewTodo(
                subagentBatchPayload: payload
            ),
            excludeCanonicalTodos: excludeCanonicalTodos
        )
        var didMutate = false
        for id in targetIDs {
            todoStore.setStatus(id: id, status: targetStatus)
            didMutate = true
        }
        if didMutate, targetStatus == .done {
            _ = todoStore.advanceNextRuntimeTodoIfNeeded(conversationId: conversationId)
        }
    }

}
