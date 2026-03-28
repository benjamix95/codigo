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
    guard let tool = canonicalTodoPolicyToolRecord(type: normalizedType, payload: payload) else {
        return false
    }
    return tool.family == "todo"
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
    guard let tool = canonicalTodoPolicyToolRecord(type: normalizedType, payload: payload) else {
        return false
    }
    return tool.family == "plan" && tool.runtimeName.hasPrefix("plan_")
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
    payload: [String: String],
    autoTodoRuntimeState: MainChatUIAutoTodoRuntimeStateBridge? = nil
) -> (errorCode: String, title: String, detail: String)? {
    guard isOperationalEventRequiringTodoPlanStartPolicy(type: type, payload: payload) else {
        return nil
    }

    let normalizedType = type
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let toolName = normalizedTodoPolicyToolName(type: normalizedType, payload: payload)
    let hasSatisfyingTodoState = state.didSeeTodoWrite || autoTodoRuntimeState != nil

    if !hasSatisfyingTodoState, !isTodoLifecycleEvent(type: normalizedType, payload: payload) {
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
    showTodoCard _: Bool = false
) -> Bool {
    let type = eventType
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if ["policy_ack", "usage", "reasoning", "turn_started", "turn_completed"].contains(type) {
        return false
    }
    let normalizedTodoTool = normalizedTodoPolicyToolName(type: type, payload: payload)
    if normalizedTodoTool == "todo_read" || normalizedTodoTool == "todo_write" {
        return false
    }
    if type == "mcp_tool_call" {
        if normalizedTodoTool == "policy_ack" {
            return false
        }
        if normalizedTodoTool == "activate_plan_mode" || normalizedTodoTool == "activate_debug_mode" {
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

    guard !rawToolName.isEmpty else { return "" }

    let namespacedPrefixes = [
        "functions.",
        "function.",
        "web.",
        "commentary.",
        "analysis.",
    ]
    var candidate = rawToolName
    for prefix in namespacedPrefixes where rawToolName.hasPrefix(prefix) {
        candidate = String(rawToolName.dropFirst(prefix.count))
        break
    }

    let mcpCoderidePrefixes = [
        "functions.mcp__coderide__coderide_",
        "mcp__coderide__coderide_",
    ]
    let loweredCandidate = candidate.lowercased()
    for prefix in mcpCoderidePrefixes where loweredCandidate.hasPrefix(prefix) {
        candidate = String(candidate.dropFirst(prefix.count))
        break
    }

    let lowered = candidate
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")
        .lowercased()
    if lowered.isEmpty { return "" }
    if let canonical = CoderIDECanonicalToolRegistry.shared.runtimeAliasesToCanonicalName[lowered] {
        return canonical
    }
    if let runtime = CoderIDECanonicalToolRegistry.shared.runtimeName(forMCPName: candidate) {
        return runtime
    }
    if let record = CoderIDECanonicalToolRegistry.shared.record(forRuntimeName: lowered) {
        return record.runtimeName.lowercased()
    }
    if lowered.hasPrefix("coderide_") {
        return String(lowered.dropFirst("coderide_".count))
    }
    return lowered
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
    let readOnlyPrefixes = [
        "cat ",
        "sed -n",
        "head ",
        "tail ",
        "less ",
        "more ",
        "awk ",
        "rg ",
        "grep ",
        "find ",
        "ls",
        "pwd",
        "wc ",
        "which ",
        "type ",
        "file ",
        "stat ",
        "plutil ",
        "readlink ",
        "test ",
        "git status",
        "git diff",
        "git show",
        "git log",
    ]
    if readOnlyPrefixes.contains(where: { lower.hasPrefix($0) }) {
        return false
    }

    return true
}

func isTodoGatedOperationalTool(_ rawToolName: String) -> Bool {
    let tool = normalizedTodoPolicyToolName(type: rawToolName, payload: [:])
    guard !tool.isEmpty else { return false }

    if tool == "policy_ack"
        || tool == "activate_plan_mode"
        || tool == "activate_debug_mode"
        || tool == "skill"
        || tool.contains("subagent_")
        || (CoderIDECanonicalToolRegistry.shared.record(forRuntimeName: tool)?.family == "audit")
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

private func canonicalTodoPolicyToolRecord(
    type: String,
    payload: [String: String]
) -> CanonicalToolRecord? {
    let normalizedType = type
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    guard normalizedType == "mcp_tool_call" else { return nil }
    let tool = normalizedTodoPolicyToolName(type: normalizedType, payload: payload)
    guard !tool.isEmpty else { return nil }
    return CoderIDECanonicalToolRegistry.shared.record(forRuntimeName: tool)
}
