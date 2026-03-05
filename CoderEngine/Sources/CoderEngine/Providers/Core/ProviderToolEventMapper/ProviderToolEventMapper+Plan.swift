import Foundation

extension ProviderToolEventMapper {
    static let planLifecycleTools: Set<String> = [
        "plan_create",
        "plan_read",
        "plan_step_upsert",
        "plan_step_batch_update",
        "plan_step_reorder",
        "plan_step_dependency_set",
        "plan_set_walkthrough",
        "plan_history_read",
        "plan_diff",
        "plan_request_user_input",
    ]

    static func isPlanLifecycleTool(_ tool: String) -> Bool {
        planLifecycleTools.contains(tool)
    }

    static func mapPlanLifecycle(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let normalized = normalizeToolIdentifier(rawTool)
        let eventType = normalized
        var mapped: [String: String] = [
            "tool": normalized,
        ]

        let scalarKeyAliases: [(output: String, aliases: [String])] = [
            ("conversation_id", ["conversation_id", "conversationId"]),
            ("goal", ["goal"]),
            ("chosen_path", ["chosen_path", "chosenPath"]),
            ("step_id", ["step_id", "stepId"]),
            ("status", ["status"]),
            ("title", ["title", "step_title", "stepTitle"]),
            ("description", ["description"]),
            ("target_file", ["target_file", "targetFile"]),
            ("notes", ["notes"]),
            ("markdown", ["markdown"]),
            ("summary", ["summary"]),
            ("outcome", ["outcome"]),
            ("from_snapshot_id", ["from_snapshot_id", "fromSnapshotId"]),
            ("to_snapshot_id", ["to_snapshot_id", "toSnapshotId"]),
            ("history_limit", ["history_limit", "historyLimit"]),
            ("limit", ["limit"]),
            ("phase", ["phase"]),
            ("round", ["round"]),
            ("context", ["context"]),
        ]
        for alias in scalarKeyAliases {
            if let value = firstString(in: payload, keys: alias.aliases), !value.isEmpty {
                mapped[alias.output] = value
            }
        }

        let jsonKeyAliases: [(output: String, aliases: [String])] = [
            ("steps", ["steps"]),
            ("updates", ["updates"]),
            ("ordered_step_ids", ["ordered_step_ids", "orderedStepIds"]),
            ("depends_on", ["depends_on", "dependsOn"]),
            ("linked_files", ["linked_files", "linkedFiles"]),
            ("questions", ["questions"]),
        ]
        for alias in jsonKeyAliases {
            if let json = alias.aliases.compactMap({ jsonString(from: payload[$0]) }).first {
                mapped[alias.output] = json
            } else if let raw = firstString(in: payload, keys: alias.aliases), !raw.isEmpty {
                mapped[alias.output] = raw
            }
        }

        if mapped["detail"] == nil {
            mapped["detail"] = planDetail(for: normalized, payload: mapped)
        }
        return (eventType, mapped)
    }

    private static func planTitle(for tool: String, payload: [String: Any]) -> String {
        switch tool {
        case "plan_create": return "Plan created"
        case "plan_read": return "Plan read"
        case "plan_step_upsert": return "Plan step upsert"
        case "plan_step_batch_update": return "Plan steps batch update"
        case "plan_step_reorder": return "Plan step order updated"
        case "plan_step_dependency_set": return "Plan step dependencies updated"
        case "plan_set_walkthrough": return "Plan walkthrough updated"
        case "plan_history_read": return "Plan history read"
        case "plan_diff": return "Plan diff computed"
        case "plan_request_user_input": return "Plan clarification requested"
        default: return payloadTitle(payload, fallback: tool)
        }
    }

    private static func planDetail(for tool: String, payload: [String: String]) -> String {
        switch tool {
        case "plan_create":
            return payload["goal"] ?? "Create plan snapshot"
        case "plan_step_upsert":
            let stepId = payload["step_id"] ?? "?"
            let status = payload["status"] ?? "pending"
            return "Step \(stepId) -> \(status)"
        case "plan_step_batch_update":
            return "Batch step update"
        case "plan_step_reorder":
            return "Reorder plan steps"
        case "plan_step_dependency_set":
            return "Update step dependencies"
        case "plan_set_walkthrough":
            return payload["summary"] ?? "Set walkthrough"
        case "plan_diff":
            return "Diff plan snapshots"
        case "plan_request_user_input":
            if let questions = payload["questions"], !questions.isEmpty {
                return "Request structured clarification input"
            }
            return "Request clarification input"
        default:
            return payload["title"] ?? tool
        }
    }

    private static func jsonString(from value: Any?) -> String? {
        guard let value else { return nil }
        if let stringValue = value as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}
