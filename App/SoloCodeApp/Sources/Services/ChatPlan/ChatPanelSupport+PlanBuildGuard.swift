import CoderEngine
import Foundation

func isPlanBuildGuardActive(
    phase: PlanFlowPhase,
    planningState: PlanningState,
    coderMode: CoderMode,
    planToggleEnabled: Bool
) -> Bool {
    let hasPlanIntent = coderMode == .plan || planToggleEnabled
    guard hasPlanIntent else { return false }

    switch phase {
    case .analyzing, .questioning, .generating, .proposalReady, .readyToBuild:
        return true
    case .idle:
        if case .awaitingClarification = planningState { return true }
        if case .awaitingChoice = planningState { return true }
        return false
    case .building:
        return false
    }
}

func planBuildGuardViolation(
    type: String,
    payload: [String: String]
) -> (errorCode: String, title: String, detail: String)? {
    let normalizedType = type
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    if isTodoLifecycleEvent(type: normalizedType, payload: payload)
        || isPlanLifecycleEvent(type: normalizedType, payload: payload)
        || normalizedType == "policy_ack"
        || normalizedType == "assistant_update"
        || normalizedType == "reasoning"
        || normalizedType == "usage"
        || normalizedType == "turn_started"
        || normalizedType == "turn_completed"
        || normalizedType == "subagent_batch_done"
        || normalizedType == "agent"
        || normalizedType == "subagent_text"
    {
        return nil
    }

    if normalizedType == "command_execution" || normalizedType == "bash" {
        guard isTodoGatedCommandExecution(payload: payload) else { return nil }
        let command = (payload["command"] ?? "command_execution")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            "plan_build_required",
            "Build required before mutation",
            "Command blocked during planning: '\(command.isEmpty ? normalizedType : command)'. Press Build to start execution."
        )
    }

    if normalizedType == "mcp_tool_call" {
        let toolName = normalizedTodoPolicyToolName(type: normalizedType, payload: payload)
        guard !toolName.isEmpty else {
            return (
                "plan_build_required",
                "Build required before mutation",
                "Unknown operational MCP tool blocked during planning. Press Build to start execution."
            )
        }

        if !isTodoGatedOperationalTool(toolName) {
            return nil
        }

        let detailTool = toolName.replacingOccurrences(of: "_", with: " ")
        return (
            "plan_build_required",
            "Build required before mutation",
            "Tool blocked during planning: '\(detailTool)'. Press Build to start execution."
        )
    }

    return nil
}
