import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func requiresTodoPlanStartPolicy(providerId: String, coderMode: CoderMode) -> Bool {
    let normalized = providerId
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    guard coderMode == .agent else { return false }
    return normalized == "codex-cli" || normalized.hasPrefix("codex")
}

func isTodoLifecycleEvent(type: String, payload: [String: String]) -> Bool {
    let normalizedType = type
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if normalizedType == "todo_write" || normalizedType == "todo_read" {
        return true
    }
    guard normalizedType == "mcp_tool_call" else { return false }
    let tool = (payload["mcp_tool"] ?? payload["tool"] ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    return tool == "coderide_todo_write" || tool == "todo_write"
        || tool == "coderide_todo_read" || tool == "todo_read"
}

func isPlanLifecycleEvent(type: String, payload: [String: String]) -> Bool {
    let normalizedType = type
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if normalizedType == "plan_create"
        || normalizedType == "plan_request_user_input"
        || normalizedType == "plan_step_upsert"
        || normalizedType == "plan_step_batch_update"
        || normalizedType == "plan_step_reorder"
        || normalizedType == "plan_step_dependency_set"
        || normalizedType == "plan_set_walkthrough"
    {
        return true
    }
    guard normalizedType == "mcp_tool_call" else { return false }
    let tool = (payload["mcp_tool"] ?? payload["tool"] ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    return tool == "coderide_plan_create" || tool == "plan_create"
        || tool == "coderide_plan_request_user_input" || tool == "plan_request_user_input"
        || tool == "coderide_plan_step_upsert" || tool == "plan_step_upsert"
        || tool == "coderide_plan_step_batch_update" || tool == "plan_step_batch_update"
        || tool == "coderide_plan_step_reorder" || tool == "plan_step_reorder"
        || tool == "coderide_plan_step_dependency_set" || tool == "plan_step_dependency_set"
        || tool == "coderide_plan_set_walkthrough" || tool == "plan_set_walkthrough"
}

func isOperationalEventRequiringTodoPlanStartPolicy(type: String, payload: [String: String]) -> Bool {
    let normalizedType = type
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if normalizedType == "policy_ack"
        || normalizedType == "activate_plan_mode"
        || normalizedType == "activate_debug_mode"
        || normalizedType == "turn_started"
        || normalizedType == "turn_completed"
        || normalizedType == "reasoning"
        || normalizedType == "usage"
        || normalizedType == "assistant_update"
        || normalizedType == "agent"
        || normalizedType == "subagent_text"
        || normalizedType == "subagent_batch_done"
        || normalizedType == "tool_validation_error"
        || normalizedType == "tool_execution_error"
        || normalizedType == "error"
    {
        return false
    }
    if isTodoLifecycleEvent(type: normalizedType, payload: payload)
        || isPlanLifecycleEvent(type: normalizedType, payload: payload)
    {
        return false
    }
    if normalizedType == "mcp_tool_call" {
        let tool = normalizedTodoPolicyToolName(type: normalizedType, payload: payload)
        return isTodoGatedOperationalTool(tool)
    }
    if isTodoDiscoveryToolEvent(type: normalizedType) {
        return false
    }
    if normalizedType == "command_execution"
        || normalizedType == "bash"
    {
        return isTodoGatedCommandExecution(payload: payload)
    }
    if normalizedType.hasPrefix("web_search") || normalizedType.hasPrefix("web_fetch") {
        return false
    }
    return false
}

func todoPlanStartPolicyViolation(
    state: ToolStartRequirementsState,
    type: String,
    payload: [String: String]
) -> (errorCode: String, title: String, detail: String)? {
    guard isOperationalEventRequiringTodoPlanStartPolicy(type: type, payload: payload) else {
        return nil
    }

    let normalizedType = type
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let toolName = normalizedTodoPolicyToolName(type: normalizedType, payload: payload)

    if !state.didSeeTodoWrite, !isTodoLifecycleEvent(type: normalizedType, payload: payload) {
        return (
            "todo_first_required",
            "Todo required before execution",
            "Emit todo_write before starting real execution with '\(toolName.isEmpty ? normalizedType : toolName)'."
        )
    }

    return nil
}

func shouldShowOperationEventInLinearChat(
    eventType: String,
    payload: [String: String],
    showTodoCard: Bool
) -> Bool {
    let type = eventType
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if ["policy_ack", "usage", "reasoning", "turn_started", "turn_completed"].contains(type) {
        return false
    }
    if showTodoCard && (type == "todo_write" || type == "todo_read") {
        return false
    }
    if type == "todo_write" || type == "todo_read" {
        return false
    }
    if type == "mcp_tool_call" {
        let tool = normalizedTodoPolicyToolName(type: type, payload: payload)
        if tool == "coderide_policy_ack" || tool == "policy_ack" {
            return false
        }
        if tool == "coderide_activate_plan_mode" || tool == "activate_plan_mode"
            || tool == "coderide_activate_debug_mode" || tool == "activate_debug_mode"
        {
            return false
        }
        if showTodoCard && (tool == "coderide_todo_write" || tool == "todo_write" || tool == "coderide_todo_read" || tool == "todo_read") {
            return false
        }
    }
    if type == "agent" || type == "subagent_text" || type == "subagent_batch_done" {
        return true
    }
    return ToolTraceVisibility.shouldDisplay(
        event: ToolTraceEvent(
            sequence: 0,
            timestamp: .distantPast,
            providerId: "",
            conversationId: UUID(),
            assistantMessageId: UUID(),
            type: type,
            title: "",
            detail: nil,
            payload: payload,
            phase: .executing,
            isRunning: false,
            groupId: nil,
            rawKind: "raw"
        )
    )
}

// MARK: - Private Tool Name / Gate Helpers

func normalizedTodoPolicyToolName(type: String, payload: [String: String]) -> String {
    let rawToolName = (
        payload["mcp_tool"]
            ?? payload["mcpTool"]
            ?? payload["tool"]
            ?? payload["toolName"]
            ?? type
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .lowercased()

    guard !rawToolName.isEmpty else { return "" }

    let namespacedPrefixes = [
        "functions.",
        "function.",
        "web.",
        "commentary.",
        "analysis.",
    ]
    for prefix in namespacedPrefixes where rawToolName.hasPrefix(prefix) {
        return String(rawToolName.dropFirst(prefix.count))
    }

    return rawToolName
}

func isTodoDiscoveryToolEvent(type: String) -> Bool {
    let normalizedType = type
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    let directDiscoveryEventTypes: Set<String> = [
        "list_mcp_resources",
        "list_mcp_resource_templates",
        "mcp_list_resources",
        "mcp_list_prompts",
    ]
    if directDiscoveryEventTypes.contains(normalizedType) {
        return true
    }
    return normalizedType.hasPrefix("functions.")
        && directDiscoveryEventTypes.contains(String(normalizedType.dropFirst("functions.".count)))
}

func isTodoGatedCommandExecution(payload: [String: String]) -> Bool {
    let command = (payload["command"] ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !command.isEmpty else { return true }

    if EventNormalizer.parseSearchQueryFromCommand(command) != nil {
        return false
    }

    let lower = command.lowercased()
    if lower.contains("cat ")
        || lower.contains("sed -n")
        || lower.contains("head ")
        || lower.contains("tail ")
        || lower.contains("less ")
        || lower.contains("more ")
        || lower.contains("awk ")
    {
        return false
    }

    return true
}

func isTodoGatedOperationalTool(_ rawToolName: String) -> Bool {
    let tool = normalizedTodoPolicyToolName(type: rawToolName, payload: [:])
    guard !tool.isEmpty else { return false }

    if tool == "coderide_policy_ack" || tool == "policy_ack"
        || tool == "coderide_activate_plan_mode" || tool == "activate_plan_mode"
        || tool == "coderide_activate_debug_mode" || tool == "activate_debug_mode"
        || tool == "coderide_skill" || tool == "skill"
        || tool.hasPrefix("coderide_audit_") || tool.hasPrefix("audit_")
        || tool.contains("subagent_")
    {
        return false
    }

    let nonMutatingDiscoveryTools: Set<String> = [
        "coderide_read", "read",
        "coderide_read_range", "read_range",
        "coderide_list_dir", "list_dir",
        "list_mcp_resources",
        "list_mcp_resource_templates",
        "mcp_list_resources",
        "mcp_list_prompts",
        "coderide_find_files", "find_files",
        "coderide_glob", "glob",
        "coderide_grep", "grep",
        "coderide_codebase_search", "codebase_search",
        "coderide_semantic_search", "semantic_search",
        "coderide_find_symbol", "find_symbol",
        "coderide_find_references", "find_references",
        "coderide_file_outline", "file_outline",
        "coderide_git_diff", "git_diff",
        "coderide_web_search", "web_search",
        "coderide_web_fetch", "web_fetch",
        "read_thread_terminal",
    ]
    if nonMutatingDiscoveryTools.contains(tool) {
        return false
    }

    return true
}
