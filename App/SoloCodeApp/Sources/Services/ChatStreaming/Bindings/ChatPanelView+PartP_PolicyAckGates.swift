import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @MainActor
    internal func shouldHardBlockForMissingPolicyAck(
        type: String,
        payload: [String: String],
        providerId: String,
        conversationId: UUID?
    ) -> Bool {
        guard uiSettings.agentsHardBlockEnabled else { return false }
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
        guard var state = toolRuntime.policyAckStateByMessage[turn.assistantMessageId] else {
            return false
        }
        if state.isSatisfied { return false }
        if state.violationEmitted { return true }

        // Hold operational events until the required policy_ack arrives.
        // ToolEnabledLLMProvider emits the ack synthetically, so this path mostly
        // protects against event reordering instead of representing a hard failure.
        state.violationEmitted = true
        toolRuntime.policyAckStateByMessage[turn.assistantMessageId] = state
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
}
