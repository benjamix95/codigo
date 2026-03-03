import Foundation

extension CodexCLIProvider {
    static func decodedJSONObject(from value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            return dict
        }
        guard let raw = value as? String else {
            return nil
        }
        return decodeJSONObjectString(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func decodeJSONObjectString(_ raw: String) -> [String: Any]? {
        let candidates: [String] = [
            raw,
            raw.replacingOccurrences(of: "\\\"", with: "\""),
        ]

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            return decoded
        }
        return nil
    }

    /// Parses Codex JSONL for structured events (file_change, command_execution, mcp_tool_call, web_search)
    static func parseRawEvent(
        from json: [String: Any],
        workspacePath: String? = nil
    ) -> (type: String, payload: [String: String])? {
        let eventType = normalizedEventType((json["type"] as? String) ?? "")
        let item = (json["item"] as? [String: Any]) ?? json
        guard let type = (item["type"] as? String) ?? (eventType.hasPrefix("item.") ? nil : eventType) else { return nil }

        if type == "reasoning" {
            let rawOutput =
                firstString(in: item, keys: ["output", "text", "reasoning", "content", "message"])
                ?? extractTextPayload(from: item)
                ?? ""
            let trimmedOutput = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedOutput.isEmpty else { return nil }

            let output = String(rawOutput.prefix(12_000))
            let detail = String(
                output
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(240)
            )
            var payload: [String: String] = [
                "title": firstString(in: item, keys: ["title", "label"]) ?? "Reasoning",
                "output": output,
                "detail": detail
            ]
            if SwarmMetadataResolver.applySwarmMetadata(to: &payload, from: item, forceGroupID: true) {
                return ("reasoning", payload)
            }

            let reasoningId =
                firstString(in: item, keys: ["group_id", "id", "reasoning_id"])
                ?? firstString(in: json, keys: ["turn_id", "id"])
                ?? ""
            if !reasoningId.isEmpty {
                payload["group_id"] = reasoningId.hasPrefix("reasoning-")
                    ? reasoningId
                    : "reasoning-\(reasoningId)"
            } else {
                payload["group_id"] = "reasoning-stream"
            }
            return ("reasoning", payload)
        }

        let activityTypes: Set<String> = [
            "file_change",
            "command_execution",
            "mcp_tool_call",
            "web_search",
            "web_fetch",
            "instant_grep",
            "todo_write",
            "todo_read",
            "plan_step_update",
            "read_batch_started",
            "read_batch_completed",
            "web_search_started",
            "web_search_completed",
            "web_search_failed",
            "web_fetch_started",
            "web_fetch_completed",
            "web_fetch_failed",
        ]
        if !activityTypes.contains(type) {
            return mapToolLikeRawEvent(type: type, eventType: eventType, item: item)
        }

        var payload: [String: String] = [
            "title": titleForType(type, item: item),
            "detail": detailForType(type, item: item),
        ]
        if let itemId = firstString(in: item, keys: ["id"]) { payload["id"] = itemId }
        if let path = firstString(
            in: item,
            keys: ["path", "file_path", "file", "target_path", "relative_path"]
        ) {
            payload["path"] = path
            payload["file"] = path
        }
        if let path = item["path"] as? String { payload["file"] = path }
        if let cmd = firstString(in: item, keys: ["command", "command_line", "cmd"]) { payload["command"] = cmd }
        if let cwd = firstString(in: item, keys: ["cwd", "working_directory", "workdir"]) { payload["cwd"] = cwd }
        if let output = firstString(in: item, keys: ["output", "result", "stdout", "message", "content", "text"]) {
            payload["output"] = String(output.prefix(6_000))
        }
        if let stderr = firstString(in: item, keys: ["stderr", "error", "error_message"]), !stderr.isEmpty {
            payload["stderr"] = String(stderr.prefix(3_000))
        }
        if let tool = firstString(in: item, keys: ["tool", "name"]) {
            payload["tool"] = ProviderToolEventMapper.normalizeToolIdentifier(tool)
            payload["tool_raw"] = tool
        }
        if let mcpTool = firstString(in: item, keys: ["mcp_tool", "tool_name"]) { payload["mcp_tool"] = mcpTool }
        if let mcpServer = firstString(in: item, keys: ["mcp_server", "server_id", "server", "server_name"]) {
            payload["mcp_server"] = mcpServer
            payload["server_id"] = payload["server_id"] ?? mcpServer
        }
        if let added = firstInt(
            in: item,
            keys: ["additions", "lines_added", "linesAdded", "insertions"]
        ) {
            payload["linesAdded"] = "\(added)"
        }
        if let removed = firstInt(
            in: item,
            keys: ["deletions", "lines_removed", "linesRemoved", "deletions_count"]
        ) {
            payload["linesRemoved"] = "\(removed)"
        }
        if type == "file_change" {
            if let diffPreview = firstString(
                in: item,
                keys: ["diffPreview", "diff", "patch", "unified_diff", "changes_preview"]
            ), !diffPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                payload["diffPreview"] = String(diffPreview.prefix(12_000))
            }
            if let changeType = firstString(
                in: item,
                keys: ["change_type", "operation", "action", "edit_type"]
            ), !changeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                payload["change_type"] = changeType
            }
            // Recompute title/detail from enriched payload for consistency.
            payload["title"] = fileChangeTitle(from: payload)
            payload["detail"] = payload["path"] ?? payload["detail"] ?? ""
            applyGitHeadFallbackIfNeeded(payload: &payload, workspacePath: workspacePath)
        }
        if let query = firstString(in: item, keys: ["query", "search_query"]) { payload["query"] = query }
        if let qid = firstString(in: item, keys: ["query_id", "id"]) { payload["queryId"] = qid }
        if let status = firstString(in: item, keys: ["status"]) { payload["status"] = status }
        if payload["status"] == nil {
            switch eventType {
            case "item.started":
                payload["status"] = "started"
            case "item.updated":
                payload["status"] = "in_progress"
            case "item.completed":
                payload["status"] = "completed"
            default:
                break
            }
        }
        if let explicitGroupId = firstString(in: item, keys: ["group_id"]), !explicitGroupId.isEmpty {
            payload["group_id"] = explicitGroupId
        }
        _ = SwarmMetadataResolver.applySwarmMetadata(to: &payload, from: item)
        if (payload["group_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let fallbackGroupId = firstString(in: item, keys: ["id"]),
           !fallbackGroupId.isEmpty {
            payload["group_id"] = fallbackGroupId
        }
        if let toolCallId = firstString(in: item, keys: ["tool_call_id", "call_id"]) { payload["tool_call_id"] = toolCallId }
        if let count = item["result_count"] as? Int { payload["resultCount"] = "\(count)" }
        if let duration = item["duration_ms"] as? Int { payload["duration_ms"] = "\(duration)" }
        if let edits = item["edit_count"] as? Int { payload["editCount"] = "\(edits)" }
        if type == "mcp_tool_call" {
            payload["is_mcp"] = "true"
            payload["title"] = mcpEventTitle(from: item)
            let detail = mcpEventDetail(from: item)
            if !detail.isEmpty {
                payload["detail"] = detail
            }
            applySubagentSwarmMetadataFromMCP(to: &payload, item: item)
        }

        return (type, payload)
    }
}
