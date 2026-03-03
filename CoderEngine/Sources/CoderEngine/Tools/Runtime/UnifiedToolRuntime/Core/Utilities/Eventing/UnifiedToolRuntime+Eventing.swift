import Foundation

extension UnifiedToolRuntime {

    // MARK: - Event Payload Builders

    func buildBasePayload(call: ToolCall, normalizedName: String) -> [String: String] {
        var payload: [String: String] = [
            "tool_call_id": call.id,
            "tool": normalizedName,
            "status": "started"
        ]
        let mcpLikeInvocation = canFallbackToMCP(toolName: normalizedName, call: call)
        if mcpLikeInvocation {
            payload["is_mcp"] = "true"
        }
        if let command = call.args["command"], !command.isEmpty {
            payload["command"] = command
            payload["title"] = "Bash"
            payload["detail"] = command
        }
        if let cwd = call.args["cwd"], !cwd.isEmpty {
            payload["cwd"] = cwd
        }
        if let query = call.args["query"], !query.isEmpty {
            payload["query"] = query
        }
        let requestedMCPTool = (call.args["tool"] ?? call.args["mcp_tool"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !requestedMCPTool.isEmpty {
            payload["mcp_tool"] = requestedMCPTool
        }
        if let url = call.args["url"], !url.isEmpty {
            payload["url"] = url
        }
        let server = resolveMCPServerArg(from: call.args)
        if !server.isEmpty {
            payload["server_id"] = server
            payload["mcp_server"] = server
        }
        if let swarmId = call.swarmId, !swarmId.isEmpty {
            payload["swarm_id"] = swarmId
            payload["group_id"] = "swarm-\(swarmId)"
        }
        return payload
}

    func startEventTypeForTool(name: String, payload: [String: String]) -> String {
        if payload["is_mcp"] == "true" {
            return "mcp_tool_call"
        }
        switch name {
        case "edit", "write", "str_replace", "create_file", "parallel_apply", "regex_replace",
             "rename_symbol", "find_and_replace_all", "undo_edit":
            return "file_change"
        case "bash":
            return "command_execution"
        case "web_search":
            return "web_search_started"
        case "web_fetch":
            return "web_fetch_started"
        case "browser_navigate", "browser_screenshot", "browser_console_logs",
             "browser_click", "browser_type", "browser_evaluate_js", "browser_get_content":
            return "browser_action_started"
        default:
            return "read_batch_started"
        }
    }

    func eventTypeForTool(name: String, ok: Bool, payload: [String: String]) -> String {
        if payload["is_mcp"] == "true" {
            return ok ? "mcp_tool_call" : "tool_execution_error"
        }
        switch name {
        case "read", "glob", "grep", "read_range", "list_dir", "git_diff", "search_symbols",
             "run_tests", "build_project", "list_processes", "read_json", "write_json",
             "workspace_stats", "dependency_audit", "tail_log",
             "codebase_search", "find_symbol", "list_symbols", "find_references",
             "project_structure", "file_outline", "find_files", "codebase_stats",
             "dependency_graph", "list_types", "list_tests", "index_status", "reindex",
             "diagnostics", "attempt_completion",
             "run_single_test",
             "semantic_search", "read_lints", "debug_context",
             "batch_read", "diff_files", "git_status", "git_show", "code_context",
             "related_files", "git_log_search":
            return ok ? "read_batch_completed" : "tool_execution_error"
        case "debug_log", "debug_query", "debug_session", "debug_hypothesize", "debug_mark", "debug_clean",
             "debug_trace_analyze", "debug_instrument", "debug_timeline", "debug_snapshot", "debug_test_check":
            return ok ? name : "tool_execution_error"
        case "edit", "write", "str_replace", "create_file", "parallel_apply", "regex_replace",
             "rename_symbol", "find_and_replace_all", "undo_edit", "apply_diff":
            return ok ? "file_change" : "tool_execution_error"
        case "bash":
            return ok ? "command_execution" : "tool_execution_error"
        case "web_search":
            return ok ? "web_search_completed" : "web_search_failed"
        case "web_fetch":
            return ok ? "web_fetch_completed" : "web_fetch_failed"
        case "browser_navigate", "browser_screenshot", "browser_console_logs",
             "browser_click", "browser_type", "browser_evaluate_js", "browser_get_content":
            return ok ? "browser_action_completed" : "browser_action_failed"
        default:
            return ok ? "command_execution" : "tool_execution_error"
        }
    }

    // MARK: - String Helpers

    func normalizeToolName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func shellEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    func truncate(_ input: String, maxBytes: Int) -> String {
        let data = input.data(using: .utf8) ?? Data()
        if data.count <= maxBytes { return input }
        let prefixData = data.prefix(maxBytes)
        let prefixText = String(data: prefixData, encoding: .utf8) ?? String(input.prefix(maxBytes / 2))
        return prefixText + "\n...[truncated]"
    }

    // MARK: - Executable Resolution

    func resolveExecutablePath(
        candidates: [String],
        commandName: String,
        cwd: String
    ) async -> String? {
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        let (output, _, exitCode) = await shellExec(
            args: ["/usr/bin/which", commandName],
            cwd: cwd,
            timeout: 2_000
        )
        guard exitCode == 0 else { return nil }
        let resolved = output
            .components(separatedBy: "\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !resolved.isEmpty, FileManager.default.isExecutableFile(atPath: resolved) else {
            return nil
        }
        return resolved
    }

    func resolveRipgrepPath(cwd: String) async -> String? {
        await resolveExecutablePath(
            candidates: [
                "/usr/bin/rg",
                "/opt/homebrew/bin/rg",
                "/usr/local/bin/rg",
            ],
            commandName: "rg",
            cwd: cwd
        )
    }

    // MARK: - File Discovery

    func discoverFilesContaining(_ needle: String, under rootPath: String) -> [String] {
        let fm = FileManager.default
        var matches: [String] = []

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: rootPath, isDirectory: &isDirectory) else {
            return []
        }

        if !isDirectory.boolValue {
            if let content = try? String(contentsOfFile: rootPath, encoding: .utf8), content.contains(needle) {
                return [rootPath]
            }
            return []
        }

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: rootPath),
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        let skippedDirectories = ExcludedDirectories.defaultSet
        let maxFileSize = 1_500_000

        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            if skippedDirectories.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]) else {
                continue
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                continue
            }
            if let size = values.fileSize, size > maxFileSize {
                continue
            }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  content.contains(needle) else {
                continue
            }
            matches.append(fileURL.path)
        }

        return matches
    }

    }
