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
        case "policy_ack", "todo_read", "todo_write", "plan_step":
            return false
        case "tool_call":
            let toolName = inferredToolName(from: marker.payload)
            if [
                "todo_read", "todo_write", "plan_step_update", "mermaid_render",
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
            "debug_phase_update", "debug_user_request", "debug_resolved",
            "activate_plan_mode", "activate_debug_mode",
            "coderide_show_task_panel", "coderide_invoke_swarm", "coderide_show_swarm_panel",
            "tool_execution_error", "tool_validation_error", "tool_timeout", "permission_denied":
            return false
        default:
            return true
        }
    }

    static func isSubagentFirstRoundExemptTool(_ toolName: String) -> Bool {
        switch toolName {
        case "todo_read", "todo_write", "plan_step_update", "mermaid_render",
             "policy_ack", "activate_plan_mode", "activate_debug_mode",
             "show_task_panel", "show_swarm_panel":
            return true
        default:
            return false
        }
    }

    static func isLegacyInvokeSwarmSuggestion(
        toolName: String,
        payload: [String: String]
    ) -> Bool {
        let normalizedTool = ProviderToolEventMapper.normalizeToolIdentifier(toolName)
        if normalizedTool == "invoke_swarm" {
            return true
        }
        guard normalizedTool == "mcp_call" else {
            return false
        }
        let targetTool = ProviderToolEventMapper.normalizeToolIdentifier(
            payload["tool"] ?? payload["mcp_tool"] ?? payload["tool_name"] ?? ""
        )
        return targetTool == "invoke_swarm"
    }

    static func isSuccessfulStatus(_ raw: String?) -> Bool {
        let status = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if status.isEmpty { return true }
        return status == "completed" || status == "ok" || status == "success" || status == "done"
    }

    static func isCodeMutationTool(_ rawTool: String) -> Bool {
        let tool = ProviderToolEventMapper.normalizeToolIdentifier(rawTool)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if tool.isEmpty { return false }
        if tool.hasPrefix("subagent_"),
           let role = SubagentRole.fromToolName(tool) {
            return role == .coder || role == .debugger
        }
        if tool == "create_file" || tool == "delete_file" || tool == "apply_patch" {
            return true
        }
        return tool.contains("edit")
            || tool.contains("write")
            || tool.contains("replace")
            || tool == "parallel_apply"
            || tool == "multi_edit"
            || tool == "find_and_replace_all"
            || tool == "rename_symbol"
            || tool == "undo_edit"
    }

    static func streamEventIndicatesCodeMutation(
        _ event: StreamEvent,
        originatingToolName: String
    ) -> Bool {
        guard case .raw(let type, let payload) = event else { return false }
        let normalizedType = type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedType == "file_change" {
            return isSuccessfulStatus(payload["status"])
        }
        if normalizedType == "mcp_tool_call" {
            let mcpTool = payload["mcp_tool"] ?? payload["tool"] ?? ""
            return isCodeMutationTool(mcpTool) && isSuccessfulStatus(payload["status"])
        }
        if normalizedType == "tool_result" {
            let tool = payload["name"] ?? originatingToolName
            return isCodeMutationTool(tool) && isSuccessfulStatus(payload["status"])
        }
        return false
    }

    static func mutatedFilePath(
        from event: StreamEvent,
        originatingToolName: String
    ) -> String? {
        guard streamEventIndicatesCodeMutation(event, originatingToolName: originatingToolName) else {
            return nil
        }
        guard case .raw(_, let payload) = event else { return nil }
        let candidates = [
            payload["path"],
            payload["file"],
            payload["filepath"],
            payload["file_path"],
            payload["target"],
        ]
        for candidate in candidates {
            guard let normalized = normalizeMutatedPath(candidate) else { continue }
            return normalized
        }
        return nil
    }

    private static func normalizeMutatedPath(_ rawPath: String?) -> String? {
        guard var value = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("`"), value.hasSuffix("`"), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        guard !value.isEmpty else { return nil }
        guard !value.contains("\n"), !value.contains("\r"), value.count <= 1024 else { return nil }
        return value
    }

    static func completedSubagentRole(from event: StreamEvent) -> SubagentRole? {
        guard case .raw(let type, let payload) = event else { return nil }
        guard type == "tool_result" else { return nil }
        guard isSuccessfulStatus(payload["status"]) else { return nil }
        let tool = payload["name"] ?? payload["tool"] ?? ""
        return SubagentRole.fromToolName(tool)
    }

    static func requiredPolicyHash(from context: WorkspaceContext) -> String? {
        let prompt = context.contextPrompt()
        guard !prompt.isEmpty else { return nil }
        // Extract the last policy_ack hash from the context prompt.
        // Matches both marker format [CODERIDE:policy_ack|hash=...] and plain hash= patterns.
        let pattern = #"\bpolicy_ack\b[^]]*\bhash=([^\s|\]\n]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsPrompt = prompt as NSString
        let matches = regex.matches(in: prompt, range: NSRange(location: 0, length: nsPrompt.length))
        // Take the last match (most recent policy hash)
        guard let lastMatch = matches.last, lastMatch.numberOfRanges >= 2 else { return nil }
        let hash = nsPrompt.substring(with: lastMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return hash.isEmpty ? nil : hash
    }

    static func matchesRequiredPolicyHash(
        _ receivedHash: String?,
        requiredHash: String?
    ) -> Bool {
        guard let requiredHash, !requiredHash.isEmpty else { return true }
        let received = (receivedHash ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !received.isEmpty && received == requiredHash
    }

}
