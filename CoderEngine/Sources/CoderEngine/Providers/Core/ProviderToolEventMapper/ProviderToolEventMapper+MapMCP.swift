import Foundation

extension ProviderToolEventMapper {
    /// When an MCP tool call's underlying tool is an IDE state tool (todo/plan),
    /// remap it to the native event type so the normalizer can route it.
    static func remapMCPIDEStateTool(tool _: String, payload: [String: Any]) -> (type: String, payload: [String: String])? {
        let mcpTool = firstString(in: payload, keys: ["mcp_tool", "tool_name"]) ?? ""
        let normalizedMCP = normalizeToolIdentifier(mcpTool)

        if normalizedMCP == "debug_panel" {
            return (
                "tool_validation_error",
                [
                    "title": "Legacy debug_panel is not supported",
                    "detail": "Use debug_set_phase, debug_request_user, debug_resolve",
                    "status": "failed",
                    "error_code": "legacy_debug_panel_removed",
                    "tool": normalizedMCP,
                ]
            )
        }

        if normalizedMCP == "todo_write" || normalizedMCP == "todo_read" {
            return mapTodo(tool: normalizedMCP, payload: payload)
        }
        if isDebugTool(normalizedMCP) {
            return mapDebug(tool: normalizedMCP, payload: payload)
        }
        if normalizedMCP == "plan_step_update" || normalizedMCP == "plan_step" {
            var mapped: [String: String] = [:]
            if let stepId = firstString(in: payload, keys: ["step_id", "stepId"]) { mapped["step_id"] = stepId }
            if let status = firstString(in: payload, keys: ["status"]) { mapped["status"] = status }
            if let title = firstString(in: payload, keys: ["title"]) { mapped["title"] = title }
            return ("plan_step_update", mapped)
        }
        if isIDEStateTool(normalizedMCP) {
            return mapIDEState(tool: normalizedMCP, payload: payload)
        }
        return nil
    }

    static func mapMCP(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let normalizedTool = normalizeToolIdentifier(rawTool)
        let mcpTool = firstString(in: payload, keys: ["mcp_tool", "tool_name", "tool"]) ?? ""
        let mcpServer = firstString(in: payload, keys: ["mcp_server", "server_id", "server"]) ?? ""
        let normalizedMCPTool = normalizeToolIdentifier(mcpTool)
        let structuredOutput = firstString(in: payload, keys: ["output", "result", "content"]).flatMap { raw in
            decodeJSONObjectString(raw)
        }
        let title: String = {
            switch normalizedTool {
            case "mcp_list_servers":
                return "MCP discovery • servers"
            case "mcp_list_tools":
                return "MCP discovery • tools"
            case "mcp_describe_tool":
                return "MCP inspect • \(mcpTool.isEmpty ? "tool" : mcpTool)"
            case "mcp_health":
                return "MCP health check"
            case "mcp_reconnect":
                return "MCP reconnect • \(mcpServer.isEmpty ? "server" : mcpServer)"
            default:
                var target = mcpTool.isEmpty ? rawTool : mcpTool
                if target.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                    target = "tool"
                }
                if !mcpServer.isEmpty {
                    return "MCP call • \(mcpServer)/\(target)"
                }
                return "MCP call • \(target)"
            }
        }()

        var mapped: [String: String] = [
            "title": title,
            "detail": firstString(in: payload, keys: ["detail", "query", "arguments", "args"]) ?? "",
            "tool": rawTool,
            "is_mcp": "true"
        ]
        if !mcpTool.isEmpty { mapped["mcp_tool"] = mcpTool }
        if !mcpServer.isEmpty {
            mapped["mcp_server"] = mcpServer
            mapped["server_id"] = mcpServer
        }
        if let status = firstString(in: payload, keys: ["status"]), !status.isEmpty {
            mapped["status"] = status
        }
        if let toolCallId = firstString(in: payload, keys: ["tool_call_id", "call_id", "id"]), !toolCallId.isEmpty {
            mapped["tool_call_id"] = toolCallId
        }
        if let added = firstInt(in: payload, keys: ["linesAdded", "additions", "insertions", "added"]) {
            mapped["linesAdded"] = "\(max(0, added))"
        }
        if let removed = firstInt(in: payload, keys: ["linesRemoved", "deletions", "removed"]) {
            mapped["linesRemoved"] = "\(max(0, removed))"
        }
        if let output = firstString(in: payload, keys: ["output", "result", "content"]), !output.isEmpty {
            mapped["output"] = String(output.prefix(6_000))
        }

        if let structuredOutput {
            if let path = firstString(in: structuredOutput, keys: ["path", "file", "file_path", "relative_path", "target_path"]), !path.isEmpty {
                mapped["path"] = mapped["path"] ?? path
                mapped["file"] = mapped["file"] ?? path
                mapped["detail"] = mapped["detail"]?.isEmpty == false ? mapped["detail"] : path
            }
            if let changeType = firstString(in: structuredOutput, keys: ["change_type", "operation", "action", "edit_type"]), !changeType.isEmpty {
                mapped["change_type"] = changeType
            }
            if let status = firstString(in: structuredOutput, keys: ["status"]), !status.isEmpty {
                mapped["status"] = status
            }
            if let toolCallId = firstString(in: structuredOutput, keys: ["tool_call_id", "call_id", "id"]), !toolCallId.isEmpty {
                mapped["tool_call_id"] = toolCallId
            }
            if let source = firstString(in: structuredOutput, keys: ["source"]), !source.isEmpty {
                mapped["source"] = source
            }
            if mapped["linesAdded"] == nil,
               let added = firstInt(in: structuredOutput, keys: ["linesAdded", "additions", "insertions", "added"]) {
                mapped["linesAdded"] = "\(max(0, added))"
            }
            if mapped["linesRemoved"] == nil,
               let removed = firstInt(in: structuredOutput, keys: ["linesRemoved", "deletions", "removed", "deletions_count"]) {
                mapped["linesRemoved"] = "\(max(0, removed))"
            }
            if let diff = firstString(
                in: structuredOutput,
                keys: ["diffPreview", "diff", "patch", "unified_diff", "changes_preview"]
            ), !diff.isEmpty {
                mapped["diffPreview"] = String(diff.prefix(12_000))
            }
        }

        if mapped["linesAdded"] == nil || mapped["linesRemoved"] == nil {
            let toolForCounters = firstString(in: payload, keys: ["mcp_tool", "tool_name", "tool_raw", "tool"]) ?? mcpTool
            if let inferred = inferReplacementSummaryLineCounters(payload: payload, toolName: toolForCounters) {
                mapped["linesAdded"] = mapped["linesAdded"] ?? "\(inferred.added)"
                mapped["linesRemoved"] = mapped["linesRemoved"] ?? "\(inferred.removed)"
            }
        }

        if let groupId = firstString(in: payload, keys: ["group_id", "groupId"]), !groupId.isEmpty {
            mapped["group_id"] = groupId
        } else if let structuredOutput,
                  let groupId = firstString(in: structuredOutput, keys: ["group_id", "groupId"]),
                  !groupId.isEmpty {
            mapped["group_id"] = groupId
        }

        var resolvedSwarmId = firstString(
            in: payload,
            keys: ["swarm_id", "swarmId", "subagent_id", "subagentId", "agent", "role"]
        )?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        if (resolvedSwarmId ?? "").isEmpty,
           let structuredOutput,
           let structuredSwarmID = firstString(
               in: structuredOutput,
               keys: ["swarm_id", "swarmId", "subagent_id", "subagentId", "agent", "role"]
           ),
           !structuredSwarmID.isEmpty {
            resolvedSwarmId = structuredSwarmID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }

        if (resolvedSwarmId ?? "").isEmpty,
           let existingGroup = mapped["group_id"]?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
           existingGroup.lowercased().hasPrefix("swarm-"),
           existingGroup.count > "swarm-".count {
            resolvedSwarmId = String(existingGroup.dropFirst("swarm-".count))
        }

        if (resolvedSwarmId ?? "").isEmpty,
           normalizedMCPTool.hasPrefix("subagent_"),
           let role = SubagentRole.fromToolName(normalizedMCPTool) {
            resolvedSwarmId = role.rawValue
        }

        if (resolvedSwarmId ?? "").isEmpty,
           normalizedMCPTool == "invoke_swarm" {
            if let explicitSwarmID = firstString(in: payload, keys: ["swarm", "swarm_name", "swarmName"]),
               !explicitSwarmID.isEmpty {
                resolvedSwarmId = explicitSwarmID
            } else if let structuredOutput,
                      let structuredSwarmID = firstString(in: structuredOutput, keys: ["swarm", "swarm_name", "swarmName"]),
                      !structuredSwarmID.isEmpty {
                resolvedSwarmId = structuredSwarmID
            } else if let token = mapped["tool_call_id"] ?? firstString(in: payload, keys: ["tool_call_id", "call_id", "id"]) {
                resolvedSwarmId = syntheticInvokeSwarmID(from: token)
            } else {
                resolvedSwarmId = "invoke-swarm"
            }
        }

        if let swarmId = resolvedSwarmId?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
           !swarmId.isEmpty {
            mapped["swarm_id"] = swarmId
            if (mapped["group_id"] ?? "").isEmpty {
                mapped["group_id"] = "swarm-\(swarmId)"
            }
        }
        return ("mcp_tool_call", mapped)
    }

    static func syntheticInvokeSwarmID(from token: String) -> String {
        let cleaned = token
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_-]"#, with: "", options: .regularExpression)
        if cleaned.isEmpty {
            return "invoke-swarm"
        }
        return "invoke-\(String(cleaned.prefix(20)))"
    }

    static let replacementSummaryRegex = try! NSRegularExpression(
        pattern: "\\((\\d+)\\s+lines?\\s*(?:->|→)\\s*(\\d+)\\s+lines?\\)",
        options: [.caseInsensitive]
    )

    static func inferReplacementSummaryLineCounters(
        payload: [String: Any],
        toolName: String
    ) -> (added: Int, removed: Int)? {
        let normalizedTool = normalizeToolIdentifier(toolName)
        let acceptsSummary = normalizedTool == "str_replace"
            || normalizedTool == "regex_replace"
            || normalizedTool == "find_and_replace_all"
            || normalizedTool == "parallel_apply"
            || normalizedTool == "multi_edit"
            || normalizedTool == "multiedit"
            || normalizedTool == "apply_patch"
            || normalizedTool == "edit"
            || normalizedTool == "write"
            || normalizedTool == "write_file"
            || normalizedTool.contains("replace")
        guard acceptsSummary else { return nil }

        let summary = firstString(in: payload, keys: ["detail", "output", "result", "content"]) ?? ""
        let trimmed = summary.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = replacementSummaryRegex.firstMatch(in: trimmed, options: [], range: range),
              let oldRange = Range(match.range(at: 1), in: trimmed),
              let newRange = Range(match.range(at: 2), in: trimmed),
              let oldLines = Int(trimmed[oldRange]),
              let newLines = Int(trimmed[newRange]) else {
            return nil
        }
        return (added: max(0, newLines), removed: max(0, oldLines))
    }
}
