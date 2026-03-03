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
    ]

    static func isPlanLifecycleTool(_ tool: String) -> Bool {
        planLifecycleTools.contains(tool)
    }

    static func mapPlanLifecycle(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let normalized = normalizeToolIdentifier(rawTool)
        let eventType = normalized
        var mapped: [String: String] = [
            "tool": normalized,
            "title": planTitle(for: normalized, payload: payload),
        ]

        let scalarKeys = [
            "conversation_id", "goal", "chosen_path",
            "step_id", "status", "title", "description",
            "target_file", "notes", "markdown", "summary", "outcome",
            "from_snapshot_id", "to_snapshot_id", "history_limit", "limit"
        ]
        for key in scalarKeys {
            if let value = firstString(in: payload, keys: [key]), !value.isEmpty {
                mapped[key] = value
            }
        }

        let jsonKeys = ["steps", "updates", "ordered_step_ids", "depends_on", "linked_files"]
        for key in jsonKeys {
            if let json = jsonString(from: payload[key]) {
                mapped[key] = json
            } else if let raw = firstString(in: payload, keys: [key]), !raw.isEmpty {
                mapped[key] = raw
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
