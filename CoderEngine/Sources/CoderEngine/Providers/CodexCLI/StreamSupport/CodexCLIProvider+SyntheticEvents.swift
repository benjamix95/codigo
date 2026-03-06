import Foundation

extension CodexCLIProvider {
    /// When an MCP tool call targets an IDE-state tool (todo/plan), produce
    /// synthetic events that feed the existing EventNormalizer → Store pipeline.
    /// The original `mcp_tool_call` event is kept for activity-panel display.
    static func syntheticIDEStateEventsFromMCP(
        payload: [String: String],
        item: [String: Any]
    ) -> [(type: String, payload: [String: String])] {
        let rawTool = (
            payload["mcp_tool"] ?? payload["tool"] ?? payload["tool_raw"] ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTool = normalizeIDEStateMCPTool(rawTool)

        let arguments = decodedJSONObject(from: item["arguments"])
            ?? decodedJSONObject(from: item["input"])
            ?? [:]
        let metadata = syntheticMCPMetadata(
            payload: payload,
            item: item,
            arguments: arguments,
            normalizedTool: normalizedTool
        )
        func wrapped(_ type: String, _ payload: [String: String]) -> (type: String, payload: [String: String]) {
            (type, mergeSyntheticPayload(payload, metadata: metadata))
        }
        let detail = (
            payload["stderr"]
            ?? payload["error"]
            ?? payload["output"]
            ?? payload["detail"]
        )
        let status = metadata["status"] ?? payload["status"]

        let sharedEvents = IDEStateSyntheticEventFactory.events(
            rawTool: rawTool,
            arguments: arguments,
            metadata: metadata,
            status: status,
            failureDetail: detail
        )
        if !sharedEvents.isEmpty || IDEStateSyntheticEventFactory.knowsTool(rawTool) {
            return sharedEvents.map { ($0.type, $0.payload) }
        }

        switch normalizedTool {
        case let t where t.hasPrefix("subagent_"):
            let task = firstString(in: arguments, keys: ["task"]) ?? ""
            guard let role = SubagentRole.fromToolName(t) else { return [] }
            let identity = SubagentExecutionIdentityBuilder.make(role: role, task: task)
            let status = (metadata["status"] ?? payload["status"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let isTerminalStatus = isTerminalMCPToolStatus(status)
            let isFailureStatus = isFailureMCPToolStatus(status)
            let explicitSwarmId = (
                firstString(in: arguments, keys: ["swarm_id"])
                ?? payload["swarm_id"]
                ?? metadata["swarm_id"]
                ?? ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let subagentId: String = {
                if !explicitSwarmId.isEmpty {
                    return explicitSwarmId
                }
                return identity.swarmId
            }()
            var events: [(type: String, payload: [String: String])] = []
            let output = firstString(in: arguments, keys: ["output"]) ?? payload["output"] ?? ""
            if isTerminalStatus {
                let detail = !output.isEmpty ? output : identity.taskSummary
                events.append(wrapped("agent", [
                    "swarm_id": subagentId,
                    "role": role.rawValue,
                    "status": isFailureStatus ? "failed" : "completed",
                    "title": identity.agentName,
                    "agent_name": identity.agentName,
                    "detail": detail,
                ]))
            } else {
                events.append(wrapped("agent", [
                    "swarm_id": subagentId,
                    "role": role.rawValue,
                    "status": status.isEmpty ? "started" : status,
                    "title": identity.agentName,
                    "agent_name": identity.agentName,
                    "detail": "launching \(role.displayName.lowercased())",
                ]))
            }
            return events

        default:
            return []
        }
    }

    private static func syntheticMCPMetadata(
        payload: [String: String],
        item: [String: Any],
        arguments: [String: Any],
        normalizedTool: String
    ) -> [String: String] {
        var metadata: [String: String] = [:]
        if let id = firstString(in: item, keys: ["id"]), !id.isEmpty {
            metadata["id"] = id
            metadata["group_id"] = id
        }
        if let groupId = firstString(in: item, keys: ["group_id"]), !groupId.isEmpty {
            metadata["group_id"] = groupId
        }
        if let payloadGroupId = payload["group_id"], !payloadGroupId.isEmpty {
            if metadata["group_id"] == nil || payloadGroupId.lowercased().hasPrefix("swarm-") {
                metadata["group_id"] = payloadGroupId
            }
        }
        if let toolCallId = firstString(in: item, keys: ["tool_call_id", "call_id"]), !toolCallId.isEmpty {
            metadata["tool_call_id"] = toolCallId
        }
        if let swarmId = payload["swarm_id"], !swarmId.isEmpty {
            metadata["swarm_id"] = swarmId
        }
        if let status = payload["status"], !status.isEmpty {
            metadata["status"] = status
        }
        if let conversationId = firstString(in: arguments, keys: ["conversation_id", "conversationId"]), !conversationId.isEmpty {
            metadata["conversation_id"] = conversationId
        }
        if let mcpTool = payload["mcp_tool"], !mcpTool.isEmpty {
            metadata["mcp_tool"] = mcpTool
        } else if !normalizedTool.isEmpty {
            metadata["mcp_tool"] = normalizedTool
        }
        if let mcpServer = payload["mcp_server"], !mcpServer.isEmpty {
            metadata["mcp_server"] = mcpServer
        }
        return metadata
    }

    private static func mergeSyntheticPayload(
        _ payload: [String: String],
        metadata: [String: String]
    ) -> [String: String] {
        var merged = metadata
        for (key, value) in payload where !value.isEmpty {
            merged[key] = value
        }
        return merged
    }

    private static func parseTodoArrayArgument(_ raw: Any?) -> [[String: Any]]? {
        if let array = raw as? [[String: Any]] {
            return array
        }
        if let rawString = raw as? String {
            let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
                return []
            }
            return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        }
        return nil
    }

    private static func jsonStringArgument(
        in arguments: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let value = arguments[key] else { continue }
            if let raw = value as? String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
                continue
            }
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8),
                  !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            return json
        }
        return nil
    }
}
