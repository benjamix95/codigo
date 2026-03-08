import Foundation

extension EventNormalizer {
    static func normalizeSpecialType(_ type: String, payload: [String: String]) -> String {
        let normalized = type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized == "mcp_tool_call", !isTrustedMCPPayload(payload) {
            return "command_execution"
        }
        let normalizedCanonicalType = remapLegacyDebugTool(normalizedToolIdentifier(normalized))
        if [
            "semantic_search", "read_lints", "debug_context",
            "debug_log", "debug_query", "debug_session", "debug_native_session",
            "debug_hypothesize", "debug_mark", "debug_clean",
            "debug_trace_analyze", "debug_instrument", "debug_timeline", "debug_snapshot", "debug_test_check",
            "debug_phase_update", "debug_user_request", "debug_resolved",
        ].contains(normalizedCanonicalType) {
            return normalizedCanonicalType
        }
        if fileChangeLikeTypes.contains(normalized) {
            return "file_change"
        }
        if normalized == "read_batch_completed",
           let rawToolName = payload["tool"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let remappedTool = remapLegacyDebugTool(rawToolName)
            if [
                "semantic_search", "read_lints", "debug_context",
                "debug_log", "debug_query", "debug_session", "debug_native_session",
                "debug_hypothesize", "debug_mark", "debug_clean",
                "debug_trace_analyze", "debug_instrument", "debug_timeline", "debug_snapshot", "debug_test_check",
                "debug_phase_update", "debug_user_request", "debug_resolved",
            ].contains(remappedTool) {
                return remappedTool
            }
        }
        if normalized == "web_search",
           let status = payload["status"]?.lowercased() {
            switch status {
            case "started":
                return "web_search_started"
            case "completed":
                return "web_search_completed"
            case "failed":
                return "web_search_failed"
            default:
                break
            }
        }
        if normalized == "web_fetch",
           let status = payload["status"]?.lowercased() {
            switch status {
            case "started":
                return "web_fetch_started"
            case "completed":
                return "web_fetch_completed"
            case "failed":
                return "web_fetch_failed"
            default:
                break
            }
        }
        return normalizedCanonicalType
    }

    static func remapLegacyDebugTool(_ raw: String) -> String {
        switch normalizedToolIdentifier(raw) {
        case "debug_set_phase":
            return "debug_phase_update"
        case "debug_request_user":
            return "debug_user_request"
        case "debug_resolve":
            return "debug_resolved"
        default:
            return normalizedToolIdentifier(raw)
        }
    }

    static func normalizedToolIdentifier(_ raw: String) -> String {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
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

    static func phaseForType(_ type: String, payload: [String: String]) -> ActivityPhase {
        switch type {
        case "command_execution", "bash":
            return .executing
        case "mcp_tool_call":
            return .executing
        case "agent":
            switch (payload["phase"] ?? "").lowercased() {
            case "thinking":
                return .thinking
            case "editing":
                return .editing
            case "searching":
                return .searching
            case "planning":
                return .planning
            default:
                return .executing
            }
        case "semantic_search":
            return .searching
        case "read_lints", "debug_context", "debug_log", "debug_query", "debug_session", "debug_native_session",
             "debug_hypothesize",
             "debug_trace_analyze", "debug_timeline", "debug_snapshot", "debug_test_check",
             "debug_phase_update", "debug_user_request", "debug_resolved":
            return .executing
        case "debug_mark", "debug_clean", "debug_instrument":
            return .editing
        case "subagent_text":
            let source = (payload["source"] ?? "").lowercased()
            return source == "reasoning" ? .thinking : .executing
        case "file_change", "edit",
             "str_replace", "regex_replace", "write", "create_file", "delete_file",
             "parallel_apply", "rename_symbol", "find_and_replace_all", "undo_edit",
             "multi_edit", "multiedit",
             "read_batch_started", "read_batch_completed":
            return .editing
        case "turn_started", "turn_completed":
            return .planning
        case "process_paused":
            return .planning
        case "process_resumed":
            return .executing
        case "instant_grep", "search",
             "web_search", "web_search_started", "web_search_completed", "web_search_failed",
             "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed":
            return .searching
        case "plan_step", "plan_step_update":
            return .planning
        case "plan_create", "plan_read", "plan_step_upsert", "plan_step_batch_update",
             "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
             "plan_history_read", "plan_diff", "plan_request_user_input":
            return .planning
        case "policy_ack":
            return .planning
        default:
            return .planning
        }
    }

    static func runningStateForType(_ type: String, payload: [String: String]) -> Bool {
        let status = payload["status"]?.lowercased()
        switch type {
        case "command_execution", "bash":
            return status == "started" || status == "running" || status == "in_progress"
        case "mcp_tool_call":
            return status == "started" || status == "running" || status == "in_progress"
        case "file_change":
            return status == "started" || status == "running" || status == "in_progress"
        case "agent":
            let detail = payload["detail"]?.lowercased()
            return detail == "started" || status == "started" || status == "running"
        case "turn_started":
            return true
        case "turn_completed":
            return false
        case "web_search_started", "web_fetch_started", "read_batch_started", "process_resumed":
            return true
        case "web_search_completed", "web_search_failed", "web_fetch_completed", "web_fetch_failed", "read_batch_completed", "process_paused":
            return false
        case "debug_log", "debug_query", "debug_session", "debug_native_session", "debug_hypothesize", "debug_mark",
             "debug_clean", "debug_trace_analyze", "debug_instrument", "debug_timeline",
             "debug_snapshot", "debug_test_check":
            return status == "started" || status == "running" || status == "in_progress"
        case "debug_phase_update":
            let normalizedPhase = (payload["phase"] ?? "").lowercased()
            return normalizedPhase != "resolved"
        case "subagent_text":
            let status = (payload["status"] ?? "").lowercased()
            if status.isEmpty { return true }
            return status == "started" || status == "running" || status == "in_progress"
        case "plan_step", "plan_step_update", "plan_step_upsert":
            let normalizedStatus = (payload["status"] ?? "").lowercased()
            return normalizedStatus == "running" || normalizedStatus == "in_progress" || normalizedStatus == "started"
        case "plan_step_batch_update":
            if let updates = payload["updates"]?.lowercased() {
                return updates.contains("\"running\"") || updates.contains("\"in_progress\"")
            }
            return false
        default:
            return false
        }
    }

    static let fileChangeLikeTypes: Set<String> = [
        "file_change",
        "edit",
        "str_replace",
        "regex_replace",
        "write",
        "create_file",
        "delete_file",
        "parallel_apply",
        "apply_patch",
        "rename_symbol",
        "find_and_replace_all",
        "undo_edit",
        "multi_edit",
        "multiedit",
        "write_file",
        "notebook_edit",
        "notebook_write",
    ]
}
