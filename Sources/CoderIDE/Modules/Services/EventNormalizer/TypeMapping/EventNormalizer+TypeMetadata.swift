import Foundation

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
        default:
            return type
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
        let rawTool = (payload["tool"] ?? payload["name"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tool = rawTool.lowercased()
        let server = (payload["mcp_server"] ?? payload["server_id"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mcpTool = (payload["mcp_tool"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = payload["detail"]

        switch tool {
        case "mcp_list_servers":
            return ("MCP discovery • servers", detail ?? "Checking available MCP servers")
        case "mcp_list_tools":
            if !server.isEmpty {
                return ("MCP discovery • tools", detail ?? "Listing tools on \(server)")
            }
            return ("MCP discovery • tools", detail ?? "Listing tools on all MCP servers")
        case "mcp_describe_tool":
            let target = !mcpTool.isEmpty ? mcpTool : "tool"
            return ("MCP inspect • \(target)", detail ?? "Inspecting tool schema")
        case "mcp_health":
            return ("MCP health check", detail ?? "Checking server health")
        case "mcp_reconnect":
            let target = server.isEmpty ? "server" : server
            return ("MCP reconnect • \(target)", detail ?? "Reconnecting MCP server")
        default:
            let isMCPLikeTool = !mcpTool.isEmpty || !server.isEmpty || isTrustedMCPPayload(payload)
            if isMCPLikeTool {
                var target = !mcpTool.isEmpty ? mcpTool : rawTool
                if target.isEmpty { target = "tool" }
                if !server.isEmpty {
                    return ("MCP call • \(server)/\(target)", detail)
                }
                return ("MCP call • \(target)", detail)
            }
            return (payload["title"] ?? "MCP operation", detail)
        }
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

    static func withSwarmPrefix(_ title: String, payload: [String: String]) -> String {
        guard let swarmId = SwarmMetadata.swarmId(from: payload) else {
            return title
        }
        if title.hasPrefix("Swarm \(swarmId)") {
            return title
        }
        return "Swarm \(swarmId) • \(title)"
    }
}
