import Foundation

extension ProviderToolEventMapper {
    private static let canonicalToolNames: Set<String> = [
        "agent", "apply_patch", "attempt_completion", "bash", "codebase_search", "command_execution", "create_file",
        "debug_clean", "debug_context", "debug_hypothesize", "debug_log", "debug_mark",
        "debug_query", "debug_session", "debug_set_phase", "debug_request_user", "debug_resolve",
        "debug_trace_analyze", "debug_instrument", "debug_timeline", "debug_snapshot", "debug_test_check",
        "delete_file", "diagnostics", "edit", "fetch_file", "file_outline",
        "file_read", "find_and_replace_all", "find_files", "find_references", "find_symbol", "glob",
        "grep", "instant_grep", "list_dir", "list_symbols", "mcp", "mcp_call", "mcp_describe_tool",
        "mcp_health", "mcp_list_servers", "mcp_list_tools", "mcp_reconnect",
        "mcp_batch", "mcp_read_resource", "mcp_subscribe", "mcp_list_prompts", "mcp_get_prompt", "mcp_logs",
        "mcp_restart_server",
        "mermaid_render", "multi_edit",
        "multiedit", "notebook_edit", "notebook_read", "notebook_write", "notebookread", "parallel_apply",
        "policy_ack",
        "plan_step_update",
        "plan_create", "plan_read", "plan_step_upsert", "plan_step_batch_update", "plan_step_reorder",
        "plan_step_dependency_set", "plan_set_walkthrough", "plan_history_read", "plan_diff",
        "plan_request_user_input",
        "read", "read_file", "read_lints", "read_range", "regex_replace", "rename_symbol", "rg",
        "run_agent", "search", "search_symbols", "semantic_search", "skill", "str_replace", "sub_agent",
        "subagent", "todo_write", "todo_read", "undo_edit", "web_fetch", "web_search", "write", "write_file",
        // IDE state tools (mode activation, task panel, swarm)
        "activate_plan_mode", "activate_debug_mode", "show_task_panel", "show_swarm_panel",
        // Subagent tools
        "subagent_explorer", "subagent_coder", "subagent_debugger", "subagent_reviewer",
        "subagent_testwriter", "subagent_docwriter", "subagent_securityauditor", "subagent_tester",
    ]

    private static let canonicalToolAliases: [String: String] = [
        "applypatch": "apply_patch",
        "codebasesearch": "codebase_search",
        "debugcontext": "debug_context",
        "debugsetphase": "debug_set_phase",
        "debugrequestuser": "debug_request_user",
        "debugresolve": "debug_resolve",
        "debugtraceanalyze": "debug_trace_analyze",
        "debuginstrument": "debug_instrument",
        "debugtimeline": "debug_timeline",
        "debugsnapshot": "debug_snapshot",
        "debugtestcheck": "debug_test_check",
        "exec_command": "bash",
        "execute_command": "bash",
        "fileoutline": "file_outline",
        "findfiles": "find_files",
        "findreferences": "find_references",
        "findsymbol": "find_symbol",
        "listdir": "list_dir",
        "listsymbols": "list_symbols",
        "mcpcall": "mcp_call",
        "mcpdescribetool": "mcp_describe_tool",
        "mcphealth": "mcp_health",
        "mcplistservers": "mcp_list_servers",
        "mcplisttools": "mcp_list_tools",
        "mcpreconnect": "mcp_reconnect",
        "multi_tool_use_parallel": "parallel_apply",
        "notebookedit": "notebook_edit",
        "notebookwrite": "notebook_write",
        "parallel": "parallel_apply",
        "readlints": "read_lints",
        "readrange": "read_range",
        "strreplace": "str_replace",
        "showswarmpanel": "show_swarm_panel",
        // Subagent aliases / normalization
        "subagent_test_writer": "subagent_testwriter",
        "subagent_doc_writer": "subagent_docwriter",
        "subagent_security_auditor": "subagent_securityauditor",
        "subagent_tester": "subagent_testwriter",
        "todowrite": "todo_write",
        "todoread": "todo_read",
        "planstepupdate": "plan_step_update",
        "plancreate": "plan_create",
        "planread": "plan_read",
        "planstepupsert": "plan_step_upsert",
        "planstepbatchupdate": "plan_step_batch_update",
        "planstepreorder": "plan_step_reorder",
        "planstepdependencyset": "plan_step_dependency_set",
        "plansetwalkthrough": "plan_set_walkthrough",
        "planhistoryread": "plan_history_read",
        "plandiff": "plan_diff",
        "planrequestuserinput": "plan_request_user_input",
        "webfetch": "web_fetch",
        "websearch": "web_search",
        "write_stdin": "bash",
        "writefile": "write_file",
        // Claude Code control tools -> IDE state equivalents
        "askuserquestion": "activate_plan_mode",
        "ask_user_question": "activate_plan_mode",
        "exitplanmode": "activate_plan_mode",
        "exit_plan_mode": "activate_plan_mode",
        "enterplanmode": "activate_plan_mode",
        "enter_plan_mode": "activate_plan_mode",
    ]

    static func normalizeToolIdentifier(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var normalized = trimmed
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()

        if normalized.hasPrefix("coderide_") {
            normalized = String(normalized.dropFirst("coderide_".count))
        }

        var candidates: [String] = [normalized]
        let components = splitToolIdentifier(normalized)
        if components.count > 1 {
            let suffixTwo = components.suffix(2).joined(separator: "_")
            candidates.append(suffixTwo)
            if let last = components.last {
                candidates.append(last)
            }
            if components.first == "mcp", components.count > 1 {
                candidates.append("mcp_" + components.dropFirst().joined(separator: "_"))
            }
        }

        for candidate in candidates {
            if let aliased = canonicalToolAliases[candidate] {
                return aliased
            }
            if canonicalToolNames.contains(candidate) {
                return candidate
            }
            if candidate.hasPrefix("mcp_") || candidate.hasPrefix("web_") {
                return candidate
            }
        }
        return normalized
    }

    static func stringify(_ value: Any) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let arr = value as? [String] { return arr.joined(separator: "\n") }
        if let arr = value as? [[String: Any]] {
            let chunks = arr.compactMap { dict -> String? in
                if let t = dict["text"] as? String { return t }
                if let c = dict["content"] as? String { return c }
                if let o = dict["output"] as? String { return o }
                return nil
            }
            if !chunks.isEmpty { return chunks.joined(separator: "\n") }
        }
        if let dict = value as? [String: Any] {
            if let t = dict["text"] as? String { return t }
            if let o = dict["output"] as? String { return o }
            if let c = dict["content"] as? String { return c }
            if let m = dict["message"] as? String { return m }
            if let e = dict["error"] as? String { return e }
        }
        return nil
    }

    private static func splitToolIdentifier(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { ch in
                ch == "." || ch == ":" || ch == "/" || ch == "\\"
            })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func expandedPayload(_ payload: [String: Any]) -> [String: Any] {
        var expanded = payload

        func merge(_ nested: [String: Any]) {
            for (key, value) in nested {
                if expanded[key] == nil {
                    expanded[key] = value
                    continue
                }
                let current = stringify(expanded[key] ?? "")?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if current.isEmpty {
                    expanded[key] = value
                }
            }
        }

        for key in ["arguments", "args", "input", "params", "parameters", "kwargs"] {
            guard let value = expanded[key] else { continue }
            if let dict = value as? [String: Any] {
                merge(dict)
                continue
            }
            if let text = value as? String, let decoded = decodeJSONObjectString(text) {
                merge(decoded)
            }
        }

        if let function = expanded["function"] as? [String: Any] {
            merge(function)
            if let arguments = function["arguments"] as? [String: Any] {
                merge(arguments)
            } else if let arguments = function["arguments"] as? String,
                      let decoded = decodeJSONObjectString(arguments) {
                merge(decoded)
            }
        }

        return expanded
    }

    static func decodeJSONObjectString(_ raw: String) -> [String: Any]? {
        let candidates: [String] = [
            raw,
            raw.replacingOccurrences(of: "\\\"", with: "\""),
        ]

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            return object
        }
        return nil
    }
}
