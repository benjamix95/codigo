import Foundation

extension ProviderToolEventMapper {
    static func mapWebSearch(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let normalized = normalizeToolIdentifier(rawTool)
        let status = normalizedStatus(fromTool: normalized, fallback: firstString(in: payload, keys: ["status"]))
        let eventType = "web_search_\(status)"
        var mapped: [String: String] = [
            "title": payloadTitle(payload, fallback: "Web search \(status)"),
            "status": status,
            "tool": normalized,
        ]
        if let query = firstString(in: payload, keys: ["query", "q"]), !query.isEmpty {
            mapped["query"] = query
            mapped["detail"] = query
        }
        if let output = firstString(in: payload, keys: ["output", "result", "content"]), !output.isEmpty {
            mapped["output"] = String(output.prefix(6_000))
        }
        return (eventType, mapped)
    }

    static func mapWebFetch(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let normalized = normalizeToolIdentifier(rawTool)
        let status = normalizedStatus(fromTool: normalized, fallback: firstString(in: payload, keys: ["status"]))
        let eventType = "web_fetch_\(status)"
        var mapped: [String: String] = [
            "title": payloadTitle(payload, fallback: "Web fetch \(status)"),
            "status": status,
            "tool": normalized,
        ]
        if let url = firstString(in: payload, keys: ["url", "link"]), !url.isEmpty {
            mapped["url"] = url
            mapped["detail"] = url
        }
        if let output = firstString(in: payload, keys: ["output", "result", "content"]), !output.isEmpty {
            mapped["output"] = String(output.prefix(6_000))
        }
        return (eventType, mapped)
    }

    static func mapAgent(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let title = payloadTitle(payload, fallback: "Agent task")
        let normalizedTool = normalizeToolIdentifier(rawTool)
        var mapped: [String: String] = [
            "title": title,
            "detail": firstString(in: payload, keys: ["detail", "task", "description"]) ?? "",
            "tool": normalizedTool,
        ]
        if let status = firstString(in: payload, keys: ["status"]), !status.isEmpty {
            mapped["status"] = status
        }
        if let groupId = firstString(in: payload, keys: ["group_id"]), !groupId.isEmpty {
            mapped["group_id"] = groupId
        }

        var resolvedSwarmId = firstString(in: payload, keys: ["swarm_id", "agent", "role"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if (resolvedSwarmId ?? "").isEmpty,
           let existingGroup = mapped["group_id"],
           existingGroup.lowercased().hasPrefix("swarm-"),
           existingGroup.count > "swarm-".count {
            resolvedSwarmId = String(existingGroup.dropFirst("swarm-".count))
        }
        if (resolvedSwarmId ?? "").isEmpty,
           let role = SubagentRole.fromToolName(normalizedTool) {
            resolvedSwarmId = role.rawValue
        }

        if let swarmId = resolvedSwarmId, !swarmId.isEmpty {
            mapped["swarm_id"] = swarmId
            if (mapped["group_id"] ?? "").isEmpty {
                mapped["group_id"] = "swarm-\(swarmId)"
            }
        }
        return ("agent", mapped)
    }

    static func mapSkill(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let skillName = firstString(in: payload, keys: ["skill", "name", "skill_name"]) ?? ""
        let args = firstString(in: payload, keys: ["args", "arguments"]) ?? ""
        let title = skillName.isEmpty ? "Skill invocation" : "Skill • \(skillName)"
        var mapped: [String: String] = [
            "title": title,
            "detail": args.isEmpty ? skillName : "\(skillName) \(args)",
            "tool": normalizeToolIdentifier(rawTool),
        ]
        if !skillName.isEmpty { mapped["skill"] = skillName }
        if !args.isEmpty { mapped["args"] = args }
        if let output = firstString(in: payload, keys: ["output", "result", "content"]), !output.isEmpty {
            mapped["output"] = String(output.prefix(6_000))
        }
        return ("skill_invocation", mapped)
    }

    static func mapDebug(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let normalizedTool = normalizeToolIdentifier(rawTool)
        var mapped: [String: String] = [
            "title": payloadTitle(payload, fallback: normalizedTool),
            "tool": normalizedTool,
        ]
        if let detail = firstString(in: payload, keys: ["detail", "message", "summary", "output"]), !detail.isEmpty {
            mapped["detail"] = detail
        }
        if let output = firstString(in: payload, keys: ["output", "result", "content"]), !output.isEmpty {
            mapped["output"] = String(output.prefix(6_000))
        }
        if let status = firstString(in: payload, keys: ["status"]), !status.isEmpty {
            mapped["status"] = status
        }
        for (key, value) in payload {
            guard mapped[key] == nil else { continue }
            if let stringValue = stringify(value), !stringValue.isEmpty {
                mapped[key] = stringValue
            }
        }
        return (normalizedTool, mapped)
    }

    static func mapIDEState(tool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        switch tool {
        case "debug_set_phase":
            var mapped: [String: String] = [:]
            if let phase = firstString(in: payload, keys: ["phase"]) { mapped["phase"] = phase }
            if let detail = firstString(in: payload, keys: ["detail"]) { mapped["detail"] = detail }
            return ("debug_phase_update", mapped)

        case "debug_request_user":
            var mapped: [String: String] = [:]
            if let kind = firstString(in: payload, keys: ["kind"]) { mapped["kind"] = kind }
            if let prompt = firstString(in: payload, keys: ["prompt"]) { mapped["prompt"] = prompt }
            return ("debug_user_request", mapped)

        case "debug_resolve":
            var mapped: [String: String] = [:]
            if let summary = firstString(in: payload, keys: ["summary", "detail", "message"]) {
                mapped["summary"] = summary
            }
            return ("debug_resolved", mapped)

        case "mermaid_render":
            var mapped: [String: String] = [:]
            if let code = firstString(in: payload, keys: ["code"]) { mapped["code"] = code }
            if let title = firstString(in: payload, keys: ["title"]) { mapped["title"] = title }
            return ("mermaid_render", mapped)

        case "policy_ack":
            var mapped: [String: String] = [:]
            if let hash = firstString(in: payload, keys: ["hash"]) { mapped["hash"] = hash }
            return ("policy_ack", mapped)

        case "activate_plan_mode":
            var mapped: [String: String] = [:]
            if let reason = firstString(in: payload, keys: ["reason", "question", "prompt", "message", "detail"]) {
                mapped["reason"] = reason
            }
            return ("activate_plan_mode", mapped)

        case "activate_debug_mode":
            var mapped: [String: String] = [:]
            if let reason = firstString(in: payload, keys: ["reason"]) { mapped["reason"] = reason }
            return ("activate_debug_mode", mapped)

        case "show_task_panel":
            return ("coderide_show_task_panel", [:])

        case "show_swarm_panel":
            var mapped: [String: String] = [:]
            if let swarmId = firstString(in: payload, keys: ["swarm_id"]) { mapped["swarm_id"] = swarmId }
            return ("coderide_show_swarm_panel", mapped)

        default:
            return ("command_execution", ["title": tool, "tool": tool])
        }
    }

    static func mapTodo(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let normalized = normalizeToolIdentifier(rawTool)
        var mapped: [String: String] = [
            "tool": normalized,
        ]

        if let todosArray = payload["todos"] as? [[String: Any]], !todosArray.isEmpty {
            if let todosData = try? JSONSerialization.data(withJSONObject: todosArray),
               let todosJson = String(data: todosData, encoding: .utf8) {
                mapped["todos_json"] = todosJson
            }
            if let firstContent = (todosArray.first?["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !firstContent.isEmpty {
                mapped["title"] = "Todo • \(firstContent)"
                mapped["detail"] = firstContent
                mapped["count"] = "\(todosArray.count)"
            } else {
                mapped["title"] = "Update todo list"
            }
        } else if let todosString = firstString(in: payload, keys: ["todos"]),
                  !todosString.isEmpty,
                  let data = todosString.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !array.isEmpty {
            if let todosData = try? JSONSerialization.data(withJSONObject: array),
               let todosJson = String(data: todosData, encoding: .utf8) {
                mapped["todos_json"] = todosJson
            }
            if let firstContent = (array.first?["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !firstContent.isEmpty {
                mapped["title"] = "Todo • \(firstContent)"
                mapped["detail"] = firstContent
                mapped["count"] = "\(array.count)"
            } else {
                mapped["title"] = "Update todo list"
            }
        } else if let title = firstString(in: payload, keys: ["title", "content"]), !title.isEmpty {
            mapped["title"] = "Todo • \(title)"
            mapped["detail"] = title
        } else {
            mapped["title"] = normalized == "todo_read" ? "Read todo list" : "Update todo list"
        }
        if let status = firstString(in: payload, keys: ["status"]), !status.isEmpty {
            mapped["status"] = status
        }
        if let activeForm = firstString(in: payload, keys: ["activeForm", "active_form"]), !activeForm.isEmpty {
            mapped["activeForm"] = activeForm
        }
        let eventType = normalized == "todo_read" ? "todo_read" : "todo_write"
        return (eventType, mapped)
    }

    static func normalizedStatus(fromTool tool: String, fallback: String?) -> String {
        if tool.hasSuffix("_started") { return "started" }
        if tool.hasSuffix("_completed") || tool.hasSuffix("_finished") { return "completed" }
        if tool.hasSuffix("_failed") || tool.hasSuffix("_error") { return "failed" }
        let normalized = normalizeToolIdentifier(fallback ?? "")
        if ["started", "running", "in_progress"].contains(normalized) { return "started" }
        if ["completed", "ok", "success", "done"].contains(normalized) { return "completed" }
        if ["failed", "error", "timeout"].contains(normalized) { return "failed" }
        return "completed"
    }

    static func intValue(from raw: Any) -> Int? {
        if let i = raw as? Int { return i }
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
}
