import Foundation

extension CodexCLIProvider {
    static func mapToolLikeRawEvent(
        type: String,
        eventType: String,
        item: [String: Any]
    ) -> (type: String, payload: [String: String])? {
        guard isToolLikeRawEvent(type: type, eventType: eventType, item: item) else { return nil }

        let explicitTool = firstString(
            in: item,
            keys: ["tool", "tool_name", "function_name", "function", "name", "mcp_tool"]
        ) ?? ""
        let normalizedType = ProviderToolEventMapper.normalizeToolIdentifier(type)
        let normalizedExplicitTool = ProviderToolEventMapper.normalizeToolIdentifier(explicitTool)
        let genericTypes: Set<String> = ["tool_call", "function_call", "tool_result", "function_result", "call"]

        let rawToolName: String
        if !normalizedExplicitTool.isEmpty {
            rawToolName = explicitTool
        } else if !genericTypes.contains(normalizedType) {
            rawToolName = type
        } else {
            return nil
        }

        guard let mapped = ProviderToolEventMapper.map(
            toolName: rawToolName,
            payload: item,
            typeHint: type
        ) else {
            return nil
        }

        var payload = mapped.payload
        if payload["tool"] == nil || payload["tool"]?.isEmpty == true {
            payload["tool"] = ProviderToolEventMapper.normalizeToolIdentifier(rawToolName)
        }

        if let status = firstString(in: item, keys: ["status"]), !status.isEmpty {
            payload["status"] = status
        } else if payload["status"] == nil {
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

        let itemId = firstString(in: item, keys: ["id"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let itemId, !itemId.isEmpty {
            payload["id"] = itemId
        }
        if let toolCallId = firstString(in: item, keys: ["tool_call_id", "call_id"]), !toolCallId.isEmpty {
            payload["tool_call_id"] = toolCallId
        } else if payload["tool_call_id"] == nil,
                  let id = payload["id"], !id.isEmpty {
            payload["tool_call_id"] = id
        }
        SwarmMetadataResolver.applySwarmMetadata(to: &payload, from: item)
        if (payload["group_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let itemId, !itemId.isEmpty {
            payload["group_id"] = itemId
        }
        if mapped.type == "mcp_tool_call" {
            applySubagentSwarmMetadataFromMCP(to: &payload, item: item)
        }

        return (mapped.type, payload)
    }

    static func applySubagentSwarmMetadataFromMCP(
        to payload: inout [String: String],
        item: [String: Any]
    ) {
        let candidates = [
            payload["mcp_tool"],
            firstString(in: item, keys: ["mcp_tool", "tool_name", "server_tool"]),
            payload["tool_raw"],
            payload["tool"],
            firstString(in: item, keys: ["tool", "name"]),
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var resolvedRole: SubagentRole?
        for candidate in candidates {
            let normalized = ProviderToolEventMapper.normalizeToolIdentifier(candidate)
            if let role = SubagentRole.fromToolName(normalized) {
                resolvedRole = role
                break
            }
        }
        guard let role = resolvedRole else { return }

        let arguments = decodedJSONObject(from: item["arguments"])
            ?? decodedJSONObject(from: item["input"])
            ?? [:]
        let task = (
            firstString(in: arguments, keys: ["task", "prompt"])
            ?? payload["detail"]
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let derivedIdentity = SubagentExecutionIdentityBuilder.make(role: role, task: task)

        let existingSwarmId = (payload["swarm_id"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let swarmId: String
        if existingSwarmId.isEmpty || existingSwarmId == role.rawValue {
            swarmId = derivedIdentity.swarmId
        } else {
            swarmId = existingSwarmId
        }
        payload["swarm_id"] = swarmId
        if (payload["agent_name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["agent_name"] = derivedIdentity.agentName
        }
        if (payload["task_summary"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !derivedIdentity.taskSummary.isEmpty {
            payload["task_summary"] = derivedIdentity.taskSummary
        }

        let currentGroupId = (payload["group_id"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if currentGroupId.isEmpty || !currentGroupId.hasPrefix("swarm-") {
            payload["group_id"] = SwarmMetadataResolver.normalizeGroupID(from: swarmId)
        }
    }
}
