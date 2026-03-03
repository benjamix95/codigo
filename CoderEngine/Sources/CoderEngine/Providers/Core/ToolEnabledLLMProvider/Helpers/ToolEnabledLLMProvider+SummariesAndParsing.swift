import Foundation

extension ToolEnabledLLMProvider {
    func summarizeToolResultEvents(_ events: [StreamEvent], marker: CoderIDEMarker) -> [String: String]? {
        var summary: [String: String] = [
            "id": marker.payload["id"] ?? UUID().uuidString,
            "name": marker.payload["name"] ?? ""
        ]
        var foundCompletion = false
        for event in events {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "tool_execution_error" || payload["status"] == "failed" {
                summary["status"] = "failed"
                summary["detail"] = payload["detail"] ?? payload["stderr"] ?? "tool failed"
                foundCompletion = true
            } else if payload["status"] == "completed" || payload["status"] == "success" {
                summary["status"] = "completed"
                summary["detail"] = payload["detail"] ?? payload["title"] ?? "ok"
                let name = (summary["name"] ?? "").lowercased()
                if let output = payload["output"], !output.isEmpty, name != "bash" && name != "command_execution" {
                    summary["output"] = String(output.prefix(8000))
                }
                if let path = payload["path"] ?? payload["file"], !path.isEmpty {
                    summary["path"] = path
                }
                foundCompletion = true
            }
        }
        return foundCompletion ? summary : nil
    }

    func buildFollowUpPrompt(originalPrompt: String, transcript: String, toolResults: [[String: String]]) -> String {
        let resultsSection: String
        if toolResults.isEmpty {
            resultsSection = """
            (No tools used in the previous round.)

            Continue the task autonomously until completion.
            If you need more tools, use tool calls and execute/verify/fix loops as needed.
            Do not stop at a plan or intention statement.
            When finished: you MUST provide a final summary to the user — what changed, which files, outcome, verification.
            """
        } else {
            let formatted = toolResults.map { result in
                let id = result["id"] ?? "-"
                let name = result["name"] ?? "-"
                let status = result["status"] ?? "unknown"
                let detail = result["detail"] ?? ""
                let path = result["path"].map { "\npath: \($0)" } ?? ""
                let nameLower = name.lowercased()
                let output: String
                if nameLower == "bash" || nameLower == "command_execution" {
                    output = ""
                } else {
                    output = result["output"].map { "\noutput:\n\($0)" } ?? ""
                }
                return "- tool_call id=\(id), name=\(name), status=\(status)\n  detail: \(detail)\(path)\(output)"
            }.joined(separator: "\n")
            resultsSection = """
            Tool results from previous round:
            \(formatted)

            Continue using these results autonomously.
            If you need more tools, use tool calls and keep iterating until done.
            If a check fails, fix and re-check before finalizing.
            When finished: you MUST provide a final summary to the user — what changed, which files, outcome, verification.
            """
        }

        return """
        \(toolProtocolPrompt)

        Original user prompt:
        \(originalPrompt)

        Conversation transcript:
        \(String(transcript.suffix(48_000)))

        \(resultsSection)
        """
    }

    func parseArgsJSON(_ raw: String) -> [String: String]? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else {
            return nil
        }
        var out: [String: String] = [:]
        for (k, v) in dict {
            if let s = v as? String {
                out[k] = s
            } else if v is NSNull {
                out[k] = "null"
            } else if let b = v as? Bool {
                out[k] = b ? "true" : "false"
            } else if let n = v as? NSNumber {
                out[k] = n.stringValue
            } else if JSONSerialization.isValidJSONObject(v) {
                if let jsonData = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys]),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    out[k] = jsonStr
                } else {
                    out[k] = String(describing: v)
                }
            } else {
                out[k] = String(describing: v)
            }
        }
        return out
    }

    func markerDedupeKey(_ marker: CoderIDEMarker) -> String {
        if marker.kind == "tool_call", let id = marker.payload["id"], !id.isEmpty {
            return "\(marker.kind)|id=\(id)"
        }
        let stablePayload = marker.payload
            .filter { $0.key.lowercased() != "id" }
            .map { key, value in "\(key)=\(value)" }
            .sorted()
            .joined(separator: "|")
        return "\(marker.kind)|\(stablePayload)"
    }

    func shouldEmitSyntheticPolicyAck(
        for marker: CoderIDEMarker,
        requiredHash: String,
        didEmitPolicyAck: Bool
    ) -> Bool {
        guard !didEmitPolicyAck else { return false }
        guard markerRequiresPolicyAck(marker) else { return false }
        return !requiredHash.isEmpty
    }

    func markerRequiresPolicyAck(_ marker: CoderIDEMarker) -> Bool {
        switch marker.kind {
        case "policy_ack", "todo_read", "todo_write", "plan_step",
             "plan_create", "plan_read", "plan_step_upsert", "plan_step_batch_update",
             "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
             "plan_history_read", "plan_diff":
            return false
        case "tool_call":
            let toolName = inferredToolName(from: marker.payload)
            if [
                "todo_read", "todo_write", "plan_step_update", "mermaid_render",
                "plan_create", "plan_read", "plan_step_upsert", "plan_step_batch_update",
                "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
                "plan_history_read", "plan_diff",
                "debug_set_phase", "debug_request_user", "debug_resolve",
                "policy_ack", "activate_plan_mode", "activate_debug_mode",
                "show_task_panel", "invoke_swarm", "show_swarm_panel",
            ].contains(toolName) {
                return false
            }
            return true
        default:
            return true
        }
    }

    func shouldEmitSyntheticPolicyAck(
        forRawEventType type: String,
        requiredHash: String,
        didEmitPolicyAck: Bool
    ) -> Bool {
        guard !didEmitPolicyAck, !requiredHash.isEmpty else { return false }
        return rawEventRequiresPolicyAck(type)
    }

    func rawEventRequiresPolicyAck(_ type: String) -> Bool {
        switch type {
        case "policy_ack", "turn_started", "turn_completed", "usage", "reasoning",
            "todo_read", "todo_write", "plan_step_update", "context_compacted",
            "plan_create", "plan_read", "plan_step_upsert", "plan_step_batch_update",
            "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
            "plan_history_read", "plan_diff",
            "debug_phase_update", "debug_user_request", "debug_resolved",
            "activate_plan_mode", "activate_debug_mode",
            "coderide_show_task_panel", "coderide_invoke_swarm", "coderide_show_swarm_panel",
            "tool_execution_error", "tool_validation_error", "tool_timeout", "permission_denied":
            return false
        default:
            return true
        }
    }

}
