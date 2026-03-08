import Foundation

extension UnifiedToolRuntime {
    static let ideStateMCPTools: Set<String> = IDEStateSyntheticEventFactory.supportedTools

    static let failureMCPStatuses: Set<String> = IDEStateSyntheticEventFactory.failureStatuses

    static func isFailureMCPToolStatus(_ normalizedStatus: String) -> Bool {
        IDEStateSyntheticEventFactory.isFailureStatus(normalizedStatus)
    }

    static func normalizeIDEStateMCPTool(_ rawTool: String) -> String {
        IDEStateSyntheticEventFactory.normalizeTool(rawTool)
    }

    static func mergedMCPCallArguments(from call: ToolCall) -> [String: Any] {
        var merged: [String: Any] = [:]
        if let richArgs = call.richArgs {
            let richAny = anyDictionary(from: richArgs)
            if let explicitArgs = richAny["args"] as? [String: Any] {
                for (key, value) in explicitArgs {
                    merged[key] = value
                }
            }
            for (key, value) in richAny where !Self.mcpWrapperKeys.contains(key) {
                merged[key] = value
            }
        }
        if let rawArgs = call.args["args"],
           let decoded = decodeJSONObjectString(rawArgs) {
            for (key, value) in decoded {
                if merged[key] == nil {
                    merged[key] = value
                }
            }
        }
        for (key, value) in call.args where !Self.mcpWrapperKeys.contains(key) {
            if merged[key] == nil {
                merged[key] = value
            }
        }
        return merged
    }

    static func decodeJSONObjectString(_ raw: String) -> [String: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.hasPrefix("{"),
              trimmed.hasSuffix("}"),
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    static func syntheticMCPMetadata(
        call: ToolCall,
        completedPayload: [String: String],
        arguments: [String: Any],
        normalizedTool: String
    ) -> [String: String] {
        var metadata: [String: String] = [:]
        if !call.id.isEmpty {
            metadata["id"] = call.id
            metadata["tool_call_id"] = call.id
            metadata["group_id"] = call.id
        }
        for key in ["tool_call_id", "group_id", "swarm_id", "status", "mcp_server", "server_id", "mcp_tool"] {
            if let value = completedPayload[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                metadata[key] = value
            }
        }
        if metadata["mcp_tool"] == nil && !normalizedTool.isEmpty {
            metadata["mcp_tool"] = normalizedTool
        }
        if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) {
            metadata["conversation_id"] = conversationID
        }
        return metadata
    }

    static func mergeSyntheticPayload(
        _ payload: [String: String],
        metadata: [String: String]
    ) -> [String: String] {
        var merged = metadata
        for (key, value) in payload where !value.isEmpty {
            merged[key] = value
        }
        return merged
    }

    static func parseTodoArrayArgument(_ raw: Any?) -> [[String: Any]]? {
        IDEStateTodoArgumentParser.parse(raw)
    }

    private static func anyDictionary(from dictionary: [String: any Sendable]) -> [String: Any] {
        var converted: [String: Any] = [:]
        for (key, value) in dictionary {
            converted[key] = anyValue(from: value)
        }
        return converted
    }

    private static func anyValue(from value: any Sendable) -> Any {
        switch value {
        case let dictionary as [String: any Sendable]:
            return anyDictionary(from: dictionary)
        case let array as [any Sendable]:
            return array.map { anyValue(from: $0) }
        default:
            return value
        }
    }

    static func mapPlanLifecycleMCPEvent(
        tool: String,
        arguments: [String: Any]
    ) -> (type: String, payload: [String: String])? {
        switch tool {
        case "plan_create":
            var payload: [String: String] = [:]
            if let goal = firstNonEmptyString(in: arguments, keys: ["goal"]) { payload["goal"] = goal }
            if let chosenPath = firstNonEmptyString(in: arguments, keys: ["chosen_path", "chosenPath"]) { payload["chosen_path"] = chosenPath }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            if let steps = jsonStringArgument(in: arguments, keys: ["steps"]) { payload["steps"] = steps }
            return payload.isEmpty ? nil : ("plan_create", payload)

        case "plan_read":
            var payload: [String: String] = [:]
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            if let includeHistory = firstNonEmptyString(in: arguments, keys: ["include_history", "includeHistory"]) { payload["include_history"] = includeHistory }
            if let historyLimit = firstNonEmptyString(in: arguments, keys: ["history_limit", "historyLimit"]) { payload["history_limit"] = historyLimit }
            return ("plan_read", payload)

        case "plan_step_upsert":
            var payload: [String: String] = [:]
            if let stepID = firstNonEmptyString(in: arguments, keys: ["step_id", "stepId"]) { payload["step_id"] = stepID }
            if let status = firstNonEmptyString(in: arguments, keys: ["status"]) { payload["status"] = status }
            if let title = firstNonEmptyString(in: arguments, keys: ["title"]) { payload["title"] = title }
            if let description = firstNonEmptyString(in: arguments, keys: ["description"]) { payload["description"] = description }
            if let targetFile = firstNonEmptyString(in: arguments, keys: ["target_file", "targetFile"]) { payload["target_file"] = targetFile }
            if let notes = firstNonEmptyString(in: arguments, keys: ["notes"]) { payload["notes"] = notes }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            if let linkedFiles = jsonStringArgument(in: arguments, keys: ["linked_files", "linkedFiles"]) { payload["linked_files"] = linkedFiles }
            if let dependsOn = jsonStringArgument(in: arguments, keys: ["depends_on", "dependsOn"]) { payload["depends_on"] = dependsOn }
            return payload.isEmpty ? nil : ("plan_step_upsert", payload)

        case "plan_step_batch_update":
            var payload: [String: String] = [:]
            if let updates = jsonStringArgument(in: arguments, keys: ["updates"]) { payload["updates"] = updates }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_step_batch_update", payload)

        case "plan_step_reorder":
            var payload: [String: String] = [:]
            if let ordered = jsonStringArgument(in: arguments, keys: ["ordered_step_ids", "orderedStepIds"]) { payload["ordered_step_ids"] = ordered }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_step_reorder", payload)

        case "plan_step_dependency_set":
            var payload: [String: String] = [:]
            if let stepID = firstNonEmptyString(in: arguments, keys: ["step_id", "stepId"]) { payload["step_id"] = stepID }
            if let dependsOn = jsonStringArgument(in: arguments, keys: ["depends_on", "dependsOn"]) { payload["depends_on"] = dependsOn }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_step_dependency_set", payload)

        case "plan_set_walkthrough":
            var payload: [String: String] = [:]
            if let markdown = firstNonEmptyString(in: arguments, keys: ["markdown"]) { payload["markdown"] = markdown }
            if let summary = firstNonEmptyString(in: arguments, keys: ["summary"]) { payload["summary"] = summary }
            if let outcome = firstNonEmptyString(in: arguments, keys: ["outcome"]) { payload["outcome"] = outcome }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_set_walkthrough", payload)

        case "plan_history_read":
            var payload: [String: String] = [:]
            if let limit = firstNonEmptyString(in: arguments, keys: ["limit"]) { payload["limit"] = limit }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return ("plan_history_read", payload)

        case "plan_diff":
            var payload: [String: String] = [:]
            if let fromSnapshotID = firstNonEmptyString(in: arguments, keys: ["from_snapshot_id", "fromSnapshotId"]) { payload["from_snapshot_id"] = fromSnapshotID }
            if let toSnapshotID = firstNonEmptyString(in: arguments, keys: ["to_snapshot_id", "toSnapshotId"]) { payload["to_snapshot_id"] = toSnapshotID }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_diff", payload)

        case "plan_request_user_input":
            var payload: [String: String] = [:]
            if let questions = jsonStringArgument(in: arguments, keys: ["questions"]) { payload["questions"] = questions }
            if let title = firstNonEmptyString(in: arguments, keys: ["title"]) { payload["title"] = title }
            if let phase = firstNonEmptyString(in: arguments, keys: ["phase"]) { payload["phase"] = phase }
            if let round = firstNonEmptyString(in: arguments, keys: ["round"]) { payload["round"] = round }
            if let context = firstNonEmptyString(in: arguments, keys: ["context"]) { payload["context"] = context }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_request_user_input", payload)

        default:
            return nil
        }
    }

    static func jsonStringArgument(
        in arguments: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let value = arguments[key] else { continue }
            if let raw = value as? String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
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

    static func firstNonEmptyString(
        in dictionary: [String: String],
        keys: [String]
    ) -> String? {
        for key in keys {
            let trimmed = (dictionary[key] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    static func firstNonEmptyString(
        in dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let text = value as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            } else if let number = value as? NSNumber {
                let text = number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }
}
