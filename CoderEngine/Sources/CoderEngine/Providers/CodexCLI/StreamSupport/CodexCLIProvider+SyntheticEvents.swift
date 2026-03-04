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
        let normalizedTool = rawTool.lowercased()
            .replacingOccurrences(of: "coderide_", with: "")
            .replacingOccurrences(of: "-", with: "_")

        let arguments = decodedJSONObject(from: item["arguments"])
            ?? decodedJSONObject(from: item["input"])
            ?? [:]

        switch normalizedTool {
        case "plan_create":
            var planPayload: [String: String] = [:]
            if let goal = firstString(in: arguments, keys: ["goal"]) { planPayload["goal"] = goal }
            if let chosenPath = firstString(in: arguments, keys: ["chosen_path"]) { planPayload["chosen_path"] = chosenPath }
            if let conversationId = firstString(in: arguments, keys: ["conversation_id"]) { planPayload["conversation_id"] = conversationId }
            if let stepsJson = jsonStringArgument(in: arguments, keys: ["steps"]) {
                planPayload["steps"] = stepsJson
            }
            guard !planPayload.isEmpty else { return [] }
            return [("plan_create", planPayload)]

        case "plan_read":
            var planPayload: [String: String] = [:]
            if let conversationId = firstString(in: arguments, keys: ["conversation_id"]) { planPayload["conversation_id"] = conversationId }
            if let includeHistory = firstString(in: arguments, keys: ["include_history"]) { planPayload["include_history"] = includeHistory }
            if let historyLimit = firstString(in: arguments, keys: ["history_limit"]) { planPayload["history_limit"] = historyLimit }
            return [("plan_read", planPayload)]

        case "plan_step_upsert":
            var planPayload: [String: String] = [:]
            if let stepId = firstString(in: arguments, keys: ["step_id", "stepId"]) { planPayload["step_id"] = stepId }
            if let status = firstString(in: arguments, keys: ["status"]) { planPayload["status"] = status }
            if let title = firstString(in: arguments, keys: ["title"]) { planPayload["title"] = title }
            if let description = firstString(in: arguments, keys: ["description"]) { planPayload["description"] = description }
            if let targetFile = firstString(in: arguments, keys: ["target_file", "targetFile"]) { planPayload["target_file"] = targetFile }
            if let notes = firstString(in: arguments, keys: ["notes"]) { planPayload["notes"] = notes }
            if let conversationId = firstString(in: arguments, keys: ["conversation_id"]) { planPayload["conversation_id"] = conversationId }
            if let linkedFiles = jsonStringArgument(in: arguments, keys: ["linked_files", "linkedFiles"]) {
                planPayload["linked_files"] = linkedFiles
            }
            if let dependsOn = jsonStringArgument(in: arguments, keys: ["depends_on", "dependsOn"]) {
                planPayload["depends_on"] = dependsOn
            }
            guard !planPayload.isEmpty else { return [] }
            return [("plan_step_upsert", planPayload)]

        case "plan_step_batch_update":
            var planPayload: [String: String] = [:]
            if let updates = jsonStringArgument(in: arguments, keys: ["updates"]) {
                planPayload["updates"] = updates
            }
            if let conversationId = firstString(in: arguments, keys: ["conversation_id"]) { planPayload["conversation_id"] = conversationId }
            guard !planPayload.isEmpty else { return [] }
            return [("plan_step_batch_update", planPayload)]

        case "plan_step_reorder":
            var planPayload: [String: String] = [:]
            if let ordered = jsonStringArgument(in: arguments, keys: ["ordered_step_ids"]) {
                planPayload["ordered_step_ids"] = ordered
            }
            if let conversationId = firstString(in: arguments, keys: ["conversation_id"]) { planPayload["conversation_id"] = conversationId }
            guard !planPayload.isEmpty else { return [] }
            return [("plan_step_reorder", planPayload)]

        case "plan_step_dependency_set":
            var planPayload: [String: String] = [:]
            if let stepId = firstString(in: arguments, keys: ["step_id"]) { planPayload["step_id"] = stepId }
            if let dependsOn = jsonStringArgument(in: arguments, keys: ["depends_on"]) {
                planPayload["depends_on"] = dependsOn
            }
            if let conversationId = firstString(in: arguments, keys: ["conversation_id"]) { planPayload["conversation_id"] = conversationId }
            guard !planPayload.isEmpty else { return [] }
            return [("plan_step_dependency_set", planPayload)]

        case "plan_set_walkthrough":
            var planPayload: [String: String] = [:]
            if let markdown = firstString(in: arguments, keys: ["markdown"]) { planPayload["markdown"] = markdown }
            if let summary = firstString(in: arguments, keys: ["summary"]) { planPayload["summary"] = summary }
            if let outcome = firstString(in: arguments, keys: ["outcome"]) { planPayload["outcome"] = outcome }
            if let conversationId = firstString(in: arguments, keys: ["conversation_id"]) { planPayload["conversation_id"] = conversationId }
            guard !planPayload.isEmpty else { return [] }
            return [("plan_set_walkthrough", planPayload)]

        case "plan_history_read":
            var planPayload: [String: String] = [:]
            if let limit = firstString(in: arguments, keys: ["limit"]) { planPayload["limit"] = limit }
            if let conversationId = firstString(in: arguments, keys: ["conversation_id"]) { planPayload["conversation_id"] = conversationId }
            return [("plan_history_read", planPayload)]

        case "plan_diff":
            var planPayload: [String: String] = [:]
            if let fromSnapshotId = firstString(in: arguments, keys: ["from_snapshot_id"]) { planPayload["from_snapshot_id"] = fromSnapshotId }
            if let toSnapshotId = firstString(in: arguments, keys: ["to_snapshot_id"]) { planPayload["to_snapshot_id"] = toSnapshotId }
            if let conversationId = firstString(in: arguments, keys: ["conversation_id"]) { planPayload["conversation_id"] = conversationId }
            guard !planPayload.isEmpty else { return [] }
            return [("plan_diff", planPayload)]

        case "plan_request_user_input":
            var planPayload: [String: String] = [:]
            if let questions = jsonStringArgument(in: arguments, keys: ["questions"]) {
                planPayload["questions"] = questions
            }
            if let title = firstString(in: arguments, keys: ["title"]) { planPayload["title"] = title }
            if let phase = firstString(in: arguments, keys: ["phase"]) { planPayload["phase"] = phase }
            if let round = firstString(in: arguments, keys: ["round"]) { planPayload["round"] = round }
            if let context = firstString(in: arguments, keys: ["context"]) { planPayload["context"] = context }
            if let conversationId = firstString(in: arguments, keys: ["conversation_id"]) {
                planPayload["conversation_id"] = conversationId
            }
            guard !planPayload.isEmpty else { return [] }
            return [("plan_request_user_input", planPayload)]

        case "todo_write":
            var todoPayload: [String: String] = [:]
            // Batch: "todos" is a JSON array string
            if let todosRaw = firstString(in: arguments, keys: ["todos"]),
               let todosData = todosRaw.data(using: .utf8),
               let todosArray = try? JSONSerialization.jsonObject(with: todosData) as? [[String: Any]],
               !todosArray.isEmpty {
                if let reEncoded = try? JSONSerialization.data(withJSONObject: todosArray),
                   let reString = String(data: reEncoded, encoding: .utf8) {
                    todoPayload["todos_json"] = reString
                }
                todoPayload["title"] = "Todo updated"
            } else {
                // Single-item shorthand
                if let t = firstString(in: arguments, keys: ["title", "content"]) { todoPayload["title"] = t }
                if let s = firstString(in: arguments, keys: ["status"]) { todoPayload["status"] = s }
                if let p = firstString(in: arguments, keys: ["priority"]) { todoPayload["priority"] = p }
                if let n = firstString(in: arguments, keys: ["notes"]) { todoPayload["notes"] = n }
            }
            // Fallback from outer payload
            if todoPayload["title"] == nil, let t = payload["title"] { todoPayload["title"] = t }
            if todoPayload["status"] == nil, let s = payload["status"] { todoPayload["status"] = s }
            if todoPayload.isEmpty { return [] }
            return [("todo_write", todoPayload)]

        case "todo_read":
            return [("todo_read", [:])]

        case "plan_step_update", "plan_step":
            var planPayload: [String: String] = [:]
            if let stepId = firstString(in: arguments, keys: ["step_id", "stepId"]) {
                planPayload["step_id"] = stepId
            }
            if let status = firstString(in: arguments, keys: ["status"]) {
                planPayload["status"] = status
            }
            if let title = firstString(in: arguments, keys: ["title"]) {
                planPayload["title"] = title
            }
            guard !planPayload.isEmpty else { return [] }
            return [("plan_step_update", planPayload)]

        case "mermaid_render":
            var p: [String: String] = [:]
            if let c = firstString(in: arguments, keys: ["code"]) { p["code"] = c }
            if let t = firstString(in: arguments, keys: ["title"]) { p["title"] = t }
            return p["code"] != nil ? [("mermaid_render", p)] : []

        case "debug_panel", "debug_panel_update":
            return [(
                "tool_validation_error",
                [
                    "title": "Legacy debug_panel is not supported",
                    "detail": "Use debug_set_phase, debug_request_user, debug_resolve",
                    "status": "failed",
                    "error_code": "legacy_debug_panel_removed",
                    "tool": normalizedTool,
                ]
            )]

        case "debug_set_phase":
            var p: [String: String] = [:]
            if let ph = firstString(in: arguments, keys: ["phase"]) { p["phase"] = ph }
            if let d = firstString(in: arguments, keys: ["detail"]) { p["detail"] = d }
            return p["phase"] != nil ? [("debug_phase_update", p)] : []

        case "debug_request_user":
            var p: [String: String] = [:]
            if let kind = firstString(in: arguments, keys: ["kind"]) { p["kind"] = kind }
            if let prompt = firstString(in: arguments, keys: ["prompt"]) { p["prompt"] = prompt }
            return (p["kind"] != nil && p["prompt"] != nil) ? [("debug_user_request", p)] : []

        case "debug_resolve":
            if let summary = firstString(in: arguments, keys: ["summary", "detail", "message"]) {
                return [("debug_resolved", ["summary": summary])]
            }
            return []

        case "policy_ack":
            if let h = firstString(in: arguments, keys: ["hash"]) { return [("policy_ack", ["hash": h])] }
            return []

        case "activate_plan_mode":
            if let reason = firstString(in: arguments, keys: ["reason"]) {
                return [("activate_plan_mode", ["reason": reason])]
            }
            return [("activate_plan_mode", [:])]

        case "activate_debug_mode":
            if let reason = firstString(in: arguments, keys: ["reason"]) {
                return [("activate_debug_mode", ["reason": reason])]
            }
            return [("activate_debug_mode", [:])]

        case "show_task_panel":
            return [("coderide_show_task_panel", [:])]

        case "show_swarm_panel":
            if let swarmId = firstString(in: arguments, keys: ["swarm_id"]) {
                return [("coderide_show_swarm_panel", ["swarm_id": swarmId])]
            }
            return [("coderide_show_swarm_panel", [:])]

        case let t where t.hasPrefix("subagent_"):
            let role = String(t.dropFirst("subagent_".count))
            let task = firstString(in: arguments, keys: ["task"]) ?? ""
            let subagentId = "\(role)-\(UUID().uuidString.prefix(8).lowercased())"
            var events: [(type: String, payload: [String: String])] = []
            events.append(("agent", [
                "swarm_id": subagentId,
                "role": role,
                "status": "started",
                "title": "Subagent \(role.capitalized) started",
                "detail": task,
            ]))
            let output = firstString(in: arguments, keys: ["output"]) ?? payload["output"] ?? ""
            if !output.isEmpty {
                events.append(("agent", [
                    "swarm_id": subagentId,
                    "role": role,
                    "status": "completed",
                    "title": "Subagent \(role.capitalized) completed",
                    "detail": output,
                ]))
            }
            return events

        default:
            return []
        }
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
