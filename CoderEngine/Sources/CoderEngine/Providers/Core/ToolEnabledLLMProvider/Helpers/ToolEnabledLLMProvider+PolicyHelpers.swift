import Foundation

extension ToolEnabledLLMProvider {
    static func isSubagentFirstRoundExemptTool(_ toolName: String) -> Bool {
        switch toolName {
        case "todo_read", "todo_write", "plan_step_update", "mermaid_render",
             "plan_create", "plan_read", "plan_step_upsert", "plan_step_batch_update",
             "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
             "plan_history_read", "plan_diff", "plan_request_user_input",
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
        // Empty/nil status is ambiguous — treat as non-success to avoid masking failures
        if status.isEmpty { return false }
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
        let knownMutatingTools: Set<String> = [
            "create_file", "delete_file", "apply_patch",
            "str_replace", "edit", "multi_edit", "regex_replace",
            "write", "parallel_apply", "find_and_replace_all",
            "rename_symbol", "undo_edit", "apply_diff",
            "coderide_str_replace", "coderide_write", "coderide_create_file",
            "coderide_regex_replace",
        ]
        if knownMutatingTools.contains(tool) { return true }
        // MCP edit tools: match only known mutation prefixes, not broad substrings
        if tool.hasPrefix("mcp_") {
            let mcpSuffix = String(tool.dropFirst(4))
            return knownMutatingTools.contains(mcpSuffix)
        }
        return false
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

    static func completedSubagentRole(from event: StreamEvent) -> SubagentRole? {
        guard case .raw(let type, let payload) = event else { return nil }
        guard type == "tool_result" else { return nil }
        guard isSuccessfulStatus(payload["status"]) else { return nil }
        // Normalize to strip "coderide_" prefix and handle casing, matching
        // the same normalization used by isCodeMutationTool.
        let tool = ProviderToolEventMapper.normalizeToolIdentifier(
            payload["name"] ?? payload["tool"] ?? ""
        )
        return SubagentRole.fromToolName(tool)
    }

    static func requiredPolicyHash(from context: WorkspaceContext) -> String? {
        let prompt = context.contextPrompt()
        guard !prompt.isEmpty else { return nil }
        let pattern = #"\bpolicy_ack\b[^\]]*\bhash=([^\s|\]\n]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsPrompt = prompt as NSString
        let matches = regex.matches(in: prompt, range: NSRange(location: 0, length: nsPrompt.length))
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

private extension ToolEnabledLLMProvider {
    static func normalizeMutatedPath(_ rawPath: String?) -> String? {
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
}
