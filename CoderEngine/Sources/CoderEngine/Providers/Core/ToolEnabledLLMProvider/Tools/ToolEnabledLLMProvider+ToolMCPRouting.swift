import Foundation

extension ToolEnabledLLMProvider {
    static func resolveLegacyInvokeSwarmRole(
        payload: [String: String],
        task: String
    ) -> SubagentRole {
        let roleCandidates = [
            payload["role"],
            payload["agent"],
            payload["swarm"],
            payload["swarm_id"],
            payload["worker"],
            payload["type"],
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

        for candidate in roleCandidates where !candidate.isEmpty {
            let normalized = candidate
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
                .lowercased()
            if let fromToolName = SubagentRole.fromToolName("subagent_\(normalized)") {
                return fromToolName
            }
            if normalized.contains("review") { return .reviewer }
            if normalized.contains("debug") { return .debugger }
            if normalized.contains("test") { return .testWriter }
            if normalized.contains("doc") { return .docWriter }
            if normalized.contains("security") || normalized.contains("audit") { return .securityAuditor }
            if normalized.contains("code") || normalized.contains("implement") { return .coder }
            if normalized.contains("explore") || normalized.contains("research") || normalized.contains("analy") {
                return .explorer
            }
        }

        let taskText = task.lowercased()
        if taskText.contains("review") { return .reviewer }
        if taskText.contains("debug") || taskText.contains("bug") { return .debugger }
        if taskText.contains("test") { return .testWriter }
        if taskText.contains("doc") { return .docWriter }
        if taskText.contains("security") || taskText.contains("audit") { return .securityAuditor }
        if taskText.contains("implement") || taskText.contains("fix") || taskText.contains("code") {
            return .coder
        }
        return .explorer
    }

    func enforcedMCPEditEventsIfNeeded(
        marker: CoderIDEMarker,
        toolName: String,
        context: WorkspaceContext
    ) async -> [StreamEvent]? {
        guard policy.enforceMCPEditOnly else { return nil }
        guard Self.mcpEditLikeTools.contains(toolName.lowercased()) else { return nil }

        guard policy.enableMCP else {
            return [
                mcpEditRequiredErrorEvent(
                    originalTool: toolName,
                    detail: "MCP-only editing is enforced, but MCP is disabled by policy.",
                    reroutedTool: nil
                )
            ]
        }

        guard let reroute = Self.rerouteEditToolToMCP(
            toolName: toolName,
            args: marker.payload
        ) else {
            return [
                mcpEditRequiredErrorEvent(
                    originalTool: toolName,
                    detail: "Tool '\(toolName)' is not reroutable to coderide MCP editing.",
                    reroutedTool: nil
                )
            ]
        }

        var reroutedArgs = reroute.args
        reroutedArgs["id"] = marker.payload["id"] ?? UUID().uuidString
        reroutedArgs["name"] = "mcp_call"
        reroutedArgs["tool"] = reroute.mcpTool
        reroutedArgs["server"] = "coderide"
        reroutedArgs["mcp_server"] = "coderide"
        reroutedArgs["mcp_tool"] = reroute.mcpTool

        let reroutedCall = ToolCall(
            id: reroutedArgs["id"] ?? UUID().uuidString,
            name: "mcp_call",
            args: reroutedArgs,
            sourceProvider: id,
            swarmId: marker.payload["swarm_id"],
            scope: executionScope
        )

        let produced = await runtime.execute(
            reroutedCall,
            context: ToolExecutionContext(
                workspaceContext: context,
                policy: policy,
                executionScope: executionScope
            )
        )

        if shouldEmitMCPEditRequiredAfterRerouteFailure(events: produced) {
            return [
                mcpEditRequiredErrorEvent(
                    originalTool: toolName,
                    detail: "Unable to use coderide MCP editing tool '\(reroute.mcpTool)'. Verify MCP server/tool availability.",
                    reroutedTool: reroute.mcpTool
                )
            ]
        }

        return produced
    }

    func shouldEmitMCPEditRequiredAfterRerouteFailure(events: [StreamEvent]) -> Bool {
        for event in events {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "mcp_tool_call", payload["status"] == "completed" {
                return false
            }
            if type == "tool_execution_error" {
                let errorCode = (payload["error_code"] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if errorCode == "mcp_unavailable" || errorCode == "validation" {
                    return true
                }
            }
        }
        return false
    }

    func mcpEditRequiredErrorEvent(
        originalTool: String,
        detail: String,
        reroutedTool: String?
    ) -> StreamEvent {
        var payload: [String: String] = [
            "title": "MCP-only editing policy violation",
            "detail": detail,
            "status": "failed",
            "error_code": "mcp_edit_required",
            "tool": originalTool,
        ]
        if let reroutedTool, !reroutedTool.isEmpty {
            payload["mcp_tool"] = reroutedTool
            payload["mcp_server"] = "coderide"
            payload["server_id"] = "coderide"
        }
        return .raw(type: "tool_validation_error", payload: payload)
    }

    struct MCPEditReroute: Sendable, Equatable {
        let mcpTool: String
        let args: [String: String]
    }

    static let mcpEditLikeTools: Set<String> = [
        "edit", "write", "str_replace", "regex_replace", "create_file", "delete_file",
        "parallel_apply", "rename_symbol", "find_and_replace_all", "undo_edit",
        "apply_patch", "multi_edit", "multiedit", "apply_diff", "write_json",
    ]

    static func rerouteEditToolToMCP(toolName: String, args: [String: String]) -> MCPEditReroute? {
        func required(_ key: String) -> String? {
            let value = (args[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : args[key]
        }

        switch toolName.lowercased() {
        case "write":
            guard let path = required("path"), let content = args["content"] else { return nil }
            return MCPEditReroute(mcpTool: "coderide_write", args: [
                "path": path,
                "content": content,
            ])
        case "edit":
            if let path = required("path"),
               let oldString = args["old_string"],
               !oldString.isEmpty,
               let newString = args["new_string"] {
                return MCPEditReroute(mcpTool: "coderide_str_replace", args: [
                    "path": path,
                    "old_string": oldString,
                    "new_string": newString,
                ])
            }
            if let path = required("path"),
               let content = args["content"] {
                return MCPEditReroute(mcpTool: "coderide_write", args: [
                    "path": path,
                    "content": content,
                ])
            }
            return nil
        case "str_replace":
            guard let path = required("path"),
                  let oldString = args["old_string"], !oldString.isEmpty,
                  let newString = args["new_string"] else { return nil }
            return MCPEditReroute(mcpTool: "coderide_str_replace", args: [
                "path": path,
                "old_string": oldString,
                "new_string": newString,
            ])
        case "regex_replace":
            guard let path = required("path"),
                  let pattern = args["pattern"], !pattern.isEmpty,
                  let replacement = args["replacement"] else { return nil }
            var reroutedArgs: [String: String] = [
                "path": path,
                "pattern": pattern,
                "replacement": replacement,
            ]
            if let flags = required("flags") {
                reroutedArgs["flags"] = flags
            }
            return MCPEditReroute(mcpTool: "coderide_regex_replace", args: reroutedArgs)
        case "create_file":
            guard let path = required("path"),
                  let content = args["content"] else { return nil }
            return MCPEditReroute(mcpTool: "coderide_create_file", args: [
                "path": path,
                "content": content,
            ])
        default:
            return nil
        }
    }

}
