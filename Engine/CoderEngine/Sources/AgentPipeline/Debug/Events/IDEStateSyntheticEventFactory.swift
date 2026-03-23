import Foundation

// MARK: - IDEStateSyntheticEvent

struct IDEStateSyntheticEvent: Sendable, Equatable {
    let type: String
    let payload: [String: String]
}

// MARK: - IDEStateSyntheticEventFactory

enum IDEStateSyntheticEventFactory {
    static let supportedTools: Set<String> = [
        "todo_write", "todo_read",
        "plan_step_update", "plan_step",
        "plan_create", "plan_read", "plan_step_upsert", "plan_step_batch_update",
        "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
        "plan_history_read", "plan_diff", "plan_request_user_input",
        "debug_set_phase", "debug_request_user", "debug_resolve",
        "policy_ack", "mermaid_render",
        "activate_plan_mode", "activate_debug_mode",
        "show_task_panel", "show_swarm_panel",
        "review_start", "review_list_sessions", "review_status",
        "review_findings", "review_apply_fix", "review_dismiss",
        "review_configure", "review_diff_summary", "review_comment",
        "review_get_outcome",
        "security_status", "security_findings",
        "bughunter_status", "bughunter_findings",
        "bughunter_run_history", "bughunter_explain_cluster",
    ]

    static let legacyRemovedTools: Set<String> = [
        "debug_panel", "debug_panel_update",
    ]

    static let failureStatuses: Set<String> = [
        "failed", "error", "cancelled", "canceled", "aborted",
        "timeout", "timed_out",
    ]

    static func normalizeTool(_ rawTool: String) -> String {
        var normalized = rawTool
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if normalized.hasPrefix("functions.") {
            normalized = String(normalized.dropFirst("functions.".count))
        }
        if normalized.hasPrefix("function.") {
            normalized = String(normalized.dropFirst("function.".count))
        }
        if normalized.hasPrefix("mcp__"),
           let namespaceSeparator = normalized.range(of: "__", options: .backwards) {
            let candidate = String(normalized[namespaceSeparator.upperBound...])
            if !candidate.isEmpty {
                normalized = candidate
            }
        }
        if let suffix = normalized.split(whereSeparator: { separator in
            separator == "." || separator == "/" || separator == ":" || separator == "\\"
        }).last {
            normalized = String(suffix)
        }
        while normalized.contains("__") {
            normalized = normalized.replacingOccurrences(of: "__", with: "_")
        }
        if normalized.hasPrefix("coderide_") {
            normalized = String(normalized.dropFirst("coderide_".count))
        }
        return normalized
    }

    static func isFailureStatus(_ normalizedStatus: String) -> Bool {
        failureStatuses.contains(normalizedStatus)
    }

    static func knowsTool(_ rawTool: String) -> Bool {
        let normalizedTool = normalizeTool(rawTool)
        return supportedTools.contains(normalizedTool)
            || legacyRemovedTools.contains(normalizedTool)
    }

    // MARK: - Helpers

    static func merge(
        _ payload: [String: String],
        metadata: [String: String]
    ) -> [String: String] {
        var merged = metadata
        for (key, value) in payload where !value.isEmpty {
            merged[key] = value
        }
        return merged
    }

    static func firstNonEmptyString(
        in dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let text = value as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let number = value as? NSNumber {
                let text = number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    static func parseTodoArrayArgument(_ raw: Any?) -> [[String: Any]]? {
        IDEStateTodoArgumentParser.parseBatchCollection(raw)
    }

    static func jsonStringArgument(
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
