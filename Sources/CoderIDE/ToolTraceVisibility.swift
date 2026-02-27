import Foundation

enum ToolTraceVisibility {
    private static let hiddenIncludeTypes: Set<String> = [
        "turn_started",
        "turn_completed",
        "coderide_show_task_panel",
        "plan_step",
        "plan_step_update",
        "activate_plan_mode",
        "activate_debug_mode",
        "planning_auto_reset",
        "reasoning",
        "usage",
    ]

    private static let hiddenDisplayTypes: Set<String> = hiddenIncludeTypes.union([
        "policy_ack",
        "todo_write",
        "todo_read",
    ])

    private static let operationalTypes: Set<String> = [
        "agent",
        "bash",
        "command_execution",
        "debug_context",
        "debug_phase_update",
        "debug_user_request",
        "debug_resolved",
        "debug_log",
        "debug_query",
        "debug_session",
        "debug_hypothesize",
        "debug_mark",
        "debug_clean",
        "edit",
        "error",
        "file_change",
        "instant_grep",
        "mcp_tool_call",
        "permission_denied",
        "read_batch_started",
        "read_batch_completed",
        "search",
        "semantic_search",
        "skill_invocation",
        "tool_execution_error",
        "tool_timeout",
        "tool_validation_error",
        "todo_read",
        "todo_write",
        "web_search",
        "web_search_started",
        "web_search_completed",
        "web_search_failed",
        "web_fetch",
        "web_fetch_started",
        "web_fetch_completed",
        "web_fetch_failed",
    ]

    private static let operationalPayloadKeys: Set<String> = [
        "command",
        "query",
        "path",
        "file",
        "files",
        "tool",
        "skill",
        "mcp_tool",
        "mcp_server",
        "server_id",
        "name",
        "pattern",
        "replacement",
        "url",
        "tool_call_id",
    ]

    static func shouldInclude(activity: TaskActivity) -> Bool {
        let type = normalizedType(activity.type)
        if type == "policy_ack" { return true }
        if hiddenIncludeTypes.contains(type) { return false }
        if type == "mcp_tool_call" {
            return isRealMCPEvent(payload: activity.payload)
        }
        if operationalTypes.contains(type) { return true }
        return hasOperationalPayload(activity.payload)
    }

    static func shouldDisplay(event: ToolTraceEvent) -> Bool {
        let type = normalizedType(event.type)
        if hiddenDisplayTypes.contains(type) { return false }
        if type == "mcp_tool_call" {
            return isRealMCPEvent(payload: event.payload)
        }
        if operationalTypes.contains(type) { return true }
        return hasOperationalPayload(event.payload)
    }

    static func shouldDisplay(activity: TaskActivity) -> Bool {
        let type = normalizedType(activity.type)
        if hiddenDisplayTypes.contains(type) { return false }
        if type == "mcp_tool_call" {
            return isRealMCPEvent(payload: activity.payload)
        }
        if operationalTypes.contains(type) { return true }
        return hasOperationalPayload(activity.payload)
    }

    static func isMCPEvent(event: ToolTraceEvent) -> Bool {
        let type = normalizedType(event.type)
        guard type == "mcp_tool_call" else { return false }
        return isRealMCPEvent(payload: event.payload)
    }

    static func isMCPEvent(activity: TaskActivity) -> Bool {
        let type = normalizedType(activity.type)
        guard type == "mcp_tool_call" else { return false }
        return isRealMCPEvent(payload: activity.payload)
    }

    static func requiresPolicyAck(type rawType: String, payload: [String: String]) -> Bool {
        let type = normalizedType(rawType)
        if type == "policy_ack" { return false }
        if type == "todo_read" || type == "todo_write" { return false }
        if hiddenDisplayTypes.contains(type) { return false }
        if [
            "tool_execution_error", "tool_validation_error", "tool_timeout",
            "permission_denied", "error"
        ].contains(type) {
            return false
        }
        if type == "mcp_tool_call" {
            return isRealMCPEvent(payload: payload)
        }
        if operationalTypes.contains(type) { return true }
        return hasOperationalPayload(payload)
    }

    private static func hasOperationalPayload(_ payload: [String: String]) -> Bool {
        for key in operationalPayloadKeys {
            let value = payload[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty {
                return true
            }
        }
        return false
    }

    private static func normalizedType(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isRealMCPEvent(payload: [String: String]) -> Bool {
        let rawTool = normalizedType(payload["tool"] ?? payload["name"] ?? "")
        let tool = normalizedToolIdentifier(rawTool)
        if rawTool.hasPrefix("mcp") || rawTool.contains(".mcp_") || rawTool.contains("/mcp_") {
            return true
        }
        if tool.hasPrefix("mcp") { return true }
        if !(payload["mcp_tool"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if !(payload["mcp_server"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if !(payload["server_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    private static func normalizedToolIdentifier(_ value: String) -> String {
        let normalized = normalizedType(value)
        guard !normalized.isEmpty else { return "" }
        let parts = normalized
            .split(whereSeparator: { ch in
                ch == "." || ch == ":" || ch == "/" || ch == "\\"
            })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let last = parts.last else { return normalized }
        return last
    }
}
