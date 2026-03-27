import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @MainActor
    internal func updateToolStartRequirementsStateIfNeeded(
        type: String,
        payload: [String: String],
        providerId: String,
        conversationId: UUID?
    ) {
        guard requiresTodoPlanStartPolicy(providerId: providerId, coderMode: coderMode) else {
            return
        }
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }
        var state = toolRuntime.toolStartRequirementsStateByMessage[turn.assistantMessageId] ?? ToolStartRequirementsState()
        if isTodoLifecycleEvent(type: type, payload: payload) {
            state.didSeeTodoWrite = true
            state.violationEmitted = false
            // #region agent log
            RuntimeEvidenceDebugLog.append(
                hypothesisId: "H46",
                location: "updateToolStartRequirementsStateIfNeeded",
                message: "todo_start_requirement_satisfied",
                data: [
                    "conversationId": conversationId?.uuidString ?? "nil",
                    "assistantMessageId": turn.assistantMessageId.uuidString,
                    "type": type,
                    "tool": payload["mcp_tool"] ?? payload["tool"] ?? "",
                    "didSeeTodoWrite": "\(state.didSeeTodoWrite)",
                    "violationEmitted": "\(state.violationEmitted)",
                ]
            )
            // #endregion
        }
        toolRuntime.toolStartRequirementsStateByMessage[turn.assistantMessageId] = state
    }

    @MainActor
    internal func shouldHardBlockForMissingTodoOrPlan(
        type: String,
        payload: [String: String],
        providerId: String,
        conversationId: UUID?
    ) -> Bool {
        guard uiSettings.agentsHardBlockEnabled else { return false }
        guard requiresTodoPlanStartPolicy(providerId: providerId, coderMode: coderMode) else {
            return false
        }
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return false
        }
        var state = toolRuntime.toolStartRequirementsStateByMessage[turn.assistantMessageId] ?? ToolStartRequirementsState()
        if let violation = todoPlanStartPolicyViolation(
            state: state,
            type: type,
            payload: payload
        ) {
            // #region agent log
            RuntimeEvidenceDebugLog.append(
                hypothesisId: "H47",
                location: "shouldHardBlockForMissingTodoOrPlan",
                message: "todo_start_policy_violation_evaluated",
                data: [
                    "conversationId": conversationId?.uuidString ?? "nil",
                    "assistantMessageId": turn.assistantMessageId.uuidString,
                    "incomingType": type,
                    "tool": payload["mcp_tool"] ?? payload["tool"] ?? "",
                    "didSeeTodoWrite": "\(state.didSeeTodoWrite)",
                    "violationEmitted": "\(state.violationEmitted)",
                    "errorCode": violation.errorCode,
                    "title": violation.title,
                    "detail": violation.detail,
                ]
            )
            // #endregion
            if !state.violationEmitted {
                state.violationEmitted = true
                toolRuntime.toolStartRequirementsStateByMessage[turn.assistantMessageId] = state
                recordTaskActivity(
                    type: "tool_validation_error",
                    payload: [
                        "title": violation.title,
                        "detail": violation.detail,
                        "status": "failed",
                        "error_code": violation.errorCode,
                        "tool": payload["mcp_tool"] ?? payload["tool"] ?? type,
                    ],
                    providerId: providerId,
                    conversationId: conversationId
                )
                appendTechnicalErrorMessage(
                    "[Policy error] \(violation.detail)",
                    in: conversationId
                )
                stopTaskForPolicyViolation(
                    conversationId: conversationId,
                    reason: "todo_plan_start_policy"
                )
            }
            return true
        }
        toolRuntime.toolStartRequirementsStateByMessage[turn.assistantMessageId] = state
        return false
    }

    /// Flush events that were queued while waiting for policy_ack.
    @MainActor
    internal func flushPolicyAckBlockedQueue(providerId: String, conversationId: UUID?) {
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }
        guard toolRuntime.policyAckStateByMessage[turn.assistantMessageId]?.isSatisfied == true else {
            return
        }
        let messageId = turn.assistantMessageId
        guard let queued = toolRuntime.policyAckBlockedQueue.removeValue(forKey: messageId), !queued.isEmpty else {
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
    internal func stopTaskForPolicyViolation(
        conversationId: UUID?,
        reason: String = "unspecified"
    ) {
        let activeAssistantMessageId = conversationId.flatMap {
            toolRuntime.activeToolTraceTurnsByConversation[$0]?.assistantMessageId
        }
        let latestAssistantLen = conversationId.flatMap { id in
            chatStore.conversation(for: id)?
                .messages
                .last(where: { $0.role == .assistant })?
                .resolvedPrimaryText
                .count
        } ?? 0
        let policyState = activeAssistantMessageId.flatMap {
            toolRuntime.policyAckStateByMessage[$0]
        }
        let blockedQueueCount = activeAssistantMessageId.flatMap {
            toolRuntime.policyAckBlockedQueue[$0]?.count
        } ?? 0
        // #region agent log
        RuntimeEvidenceDebugLog.append(
            hypothesisId: "H9",
            location: "stopTaskForPolicyViolation",
            message: "policy_violation_stop_requested",
            data: [
                "conversationId": conversationId?.uuidString ?? "nil",
                "reason": reason,
                "assistantMessageId": activeAssistantMessageId?.uuidString ?? "nil",
                "expectedHash": policyState?.expectedHash ?? "",
                "acknowledgedHash": policyState?.acknowledgedHash ?? "",
                "isSatisfied": "\(policyState?.isSatisfied == true)",
                "blockedQueueCount": "\(blockedQueueCount)",
                "latestAssistantLen": "\(latestAssistantLen)",
            ]
        )
        // #endregion
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
        conversationRuntime.taskFlushTask?.cancel()
        conversationRuntime.taskFlushTask = nil
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
