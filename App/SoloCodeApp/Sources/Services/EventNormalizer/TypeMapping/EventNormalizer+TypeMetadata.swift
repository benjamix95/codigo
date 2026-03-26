import CoderEngine
import Foundation

func userFacingToolName(
    from payload: [String: String],
    fallback: String = "tool"
) -> String {
    let rawCandidates = [
        payload["mcp_tool"],
        payload["mcpTool"],
        payload["tool"],
        payload["name"],
    ]
    for candidate in rawCandidates {
        let trimmed = candidate?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { continue }

        let suffix = trimmed.components(separatedBy: "/").last ?? trimmed
        var normalized = suffix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Rimuovi solo prefissi provider/host; lasciare intatto `mcp_*` così le etichette UI risolvono bene.
        let prefixes = [
            "functions.mcp__coderide__coderide_",
            "mcp__coderide__coderide_",
            "coderide_",
        ]
        for prefix in prefixes where normalized.hasPrefix(prefix) {
            normalized = String(normalized.dropFirst(prefix.count))
            break
        }

        if !normalized.isEmpty {
            return AgentToolUIDisplayName.label(forRuntimeTool: normalized)
        }
    }
    return AgentToolUIDisplayName.label(forRuntimeTool: fallback)
}

extension EventNormalizer {
    static func defaultTitle(for type: String) -> String {
        switch type {
        case "process_paused":
            return "Process paused"
        case "process_resumed":
            return "Process resumed"
        case "read_batch_started":
            return "File batch read started"
        case "read_batch_completed":
            return "File batch read completed"
        case "turn_started":
            return "Turn started"
        case "turn_completed":
            return "Turn completed"
        case "web_search_started":
            return "Web search started"
        case "web_search_completed":
            return "Web search completed"
        case "web_search_failed":
            return "Web search failed"
        case "web_fetch_started":
            return "Fetching web page"
        case "web_fetch_completed":
            return "Web page fetched"
        case "web_fetch_failed":
            return "Web fetch failed"
        case "tool_execution_error":
            return "Tool execution error"
        case "tool_validation_error":
            return "Tool validation error"
        case "tool_timeout":
            return "Timeout tool"
        case "permission_denied":
            return "Permission denied"
        case "debug_log":
            return "Debug log"
        case "debug_query":
            return "Debug query"
        case "debug_session":
            return "Debug session"
        case "debug_native_session":
            return "Native debug session"
        case "debug_hypothesize":
            return "Debug hypothesis"
        case "debug_mark":
            return "Debug marker"
        case "debug_clean":
            return "Debug clean"
        case "debug_trace_analyze":
            return "Debug trace analysis"
        case "debug_instrument":
            return "Debug instrumentation"
        case "debug_timeline":
            return "Debug timeline"
        case "debug_snapshot":
            return "Debug snapshot"
        case "debug_test_check":
            return "Debug test check"
        case "debug_phase_update":
            return "Debug phase update"
        case "debug_user_request":
            return "Debug user request"
        case "debug_resolved":
            return "Debug resolved"
        case "policy_ack":
            return "Policy acknowledged"
        case "plan_create":
            return "Plan created"
        case "plan_read":
            return "Plan read"
        case "plan_step_upsert":
            return "Plan step upsert"
        case "plan_step_batch_update":
            return "Plan steps batch update"
        case "plan_step_reorder":
            return "Plan step order updated"
        case "plan_step_dependency_set":
            return "Plan step dependencies updated"
        case "plan_set_walkthrough":
            return "Plan walkthrough updated"
        case "plan_history_read":
            return "Plan history read"
        case "plan_diff":
            return "Plan diff computed"
        case "plan_request_user_input":
            return "Plan clarification requested"
        case "codex_thread_token_usage":
            return "Thread token usage updated"
        case "codex_thread_status":
            return "Thread status changed"
        case "codex_rate_limits_updated":
            return "Codex rate limits updated"
        case "codex_turn_diff":
            return "Turn diff updated"
        case "codex_context_compaction":
            return "Context compaction"
        default:
            return AgentToolUIDisplayName.label(forRuntimeTool: type)
        }
    }

    static func debugFlowPhase(from raw: String?) -> DebugFlowPhase? {
        guard let raw else { return nil }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let phase = DebugFlowPhase(rawValue: normalized) {
            return phase
        }
        switch normalized {
        case "analyze", "analysis", "analyzing", "describe":
            return .describing
        case "reproduce":
            return .reproducing
        case "fix":
            return .fixing
        case "instrument":
            return .instrumenting
        case "verify":
            return .verifying
        case "resolve":
            return .resolved
        default:
            return nil
        }
    }

    static func mcpTitleAndDetail(payload: [String: String]) -> (title: String, detail: String?) {
        guard isTrustedMCPPayload(payload) else {
            return (payload["title"] ?? "MCP operation", payload["detail"])
        }
        let detail = payload["detail"]
        return (userFacingToolName(from: payload), detail)
    }

    static func isTrustedMCPPayload(_ payload: [String: String]) -> Bool {
        let marker = (payload["is_mcp"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if marker == "true" || marker == "1" || marker == "yes" {
            return true
        }
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

    /// Associates title with its swarm context without exposing raw internal IDs.
    /// Uses the readable_name from the payload when available, never the raw swarm_id.
    static func withSwarmPrefix(_ title: String, payload: [String: String]) -> String {
        guard SwarmMetadata.swarmId(from: payload) != nil else {
            return title
        }
        // Use readable_name if available, never raw swarm_id
        if let readable = payload["readable_name"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !readable.isEmpty,
           !title.lowercased().contains(readable.lowercased()) {
            return "\(readable) • \(title)"
        }
        // If title already contains meaningful context, return as-is
        return title
    }
}
