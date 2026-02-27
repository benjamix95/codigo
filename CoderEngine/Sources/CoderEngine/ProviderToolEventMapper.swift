import Foundation

enum ProviderToolEventMapper {
    static func map(
        toolName rawToolName: String,
        payload: [String: Any],
        typeHint: String? = nil
    ) -> (type: String, payload: [String: String])? {
        let normalizedPayload = expandedPayload(payload)
        let normalizedTool = normalizeToolIdentifier(rawToolName)
        let normalizedHint = normalizeToolIdentifier(typeHint ?? "")
        let tool = normalizedTool.isEmpty ? normalizedHint : normalizedTool

        let mappedToolName = tool.isEmpty ? rawToolName : tool

        if isCommandTool(tool: tool, payload: normalizedPayload, typeHint: normalizedHint) {
            return mapCommand(tool: mappedToolName, payload: normalizedPayload)
        }
        if isReadTool(tool) {
            return mapRead(tool: mappedToolName, payload: normalizedPayload)
        }
        if isFileChangeTool(tool, typeHint: normalizedHint) {
            return mapFileChange(tool: mappedToolName, payload: normalizedPayload, typeHint: normalizedHint)
        }
        if isSemanticTool(tool) {
            return mapSemantic(tool: mappedToolName, payload: normalizedPayload)
        }
        if isSearchTool(tool) {
            return mapSearch(tool: mappedToolName, payload: normalizedPayload)
        }
        if isMCPTool(tool, payload: normalizedPayload) {
            // MCP tool calls that target IDE state tools (todo/plan) should be
            // remapped to their native event types so the UI pipeline handles them.
            if let ideRemap = remapMCPIDEStateTool(tool: mappedToolName, payload: normalizedPayload) {
                return ideRemap
            }
            return mapMCP(tool: mappedToolName, payload: normalizedPayload)
        }
        if isWebSearchTool(tool, payload: normalizedPayload) {
            return mapWebSearch(tool: mappedToolName, payload: normalizedPayload)
        }
        if isWebFetchTool(tool, payload: normalizedPayload) {
            return mapWebFetch(tool: mappedToolName, payload: normalizedPayload)
        }
        if isSkillTool(tool) {
            return mapSkill(tool: mappedToolName, payload: normalizedPayload)
        }
        if isAgentTool(tool) {
            return mapAgent(tool: mappedToolName, payload: normalizedPayload)
        }
        if isTodoTool(tool) {
            return mapTodo(tool: mappedToolName, payload: normalizedPayload)
        }
        if isIDEStateTool(tool) {
            return mapIDEState(tool: tool, payload: normalizedPayload)
        }
        if !tool.isEmpty {
            return mapFallback(tool: mappedToolName, payload: normalizedPayload)
        }
        return nil
    }

    static func firstString(in input: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = input[key], let stringValue = stringify(value), !stringValue.isEmpty {
                return stringValue
            }
        }
        for (_, value) in input {
            if let nested = value as? [String: Any], let found = firstString(in: nested, keys: keys) {
                return found
            }
            if let list = value as? [Any] {
                for item in list {
                    if let nested = item as? [String: Any], let found = firstString(in: nested, keys: keys) {
                        return found
                    }
                }
            }
        }
        return nil
    }

    static func firstInt(in input: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = input[key] {
                if let intValue = intValue(from: value) {
                    return intValue
                }
            }
        }
        for (_, value) in input {
            if let nested = value as? [String: Any], let found = firstInt(in: nested, keys: keys) {
                return found
            }
            if let list = value as? [Any] {
                for item in list {
                    if let nested = item as? [String: Any], let found = firstInt(in: nested, keys: keys) {
                        return found
                    }
                }
            }
        }
        return nil
    }

    static func fileChangeTitle(path: String, changeType: String) -> String {
        let base = (path as NSString).lastPathComponent
        let normalized = normalizeToolIdentifier(changeType)
        if normalized.contains("create") || normalized.contains("add") || normalized == "write_new" {
            return "Created \(base)"
        }
        if normalized.contains("delete") || normalized.contains("remove") {
            return "Deleted \(base)"
        }
        return "Edited \(base)"
    }

    static func buildDiffPreview(old: String, new: String) -> String {
        let oldLines = old.components(separatedBy: .newlines)
        let newLines = new.components(separatedBy: .newlines)
        var out: [String] = []
        out.append("--- old")
        out.append("+++ new")
        let commonPrefixCount = zip(oldLines, newLines).prefix { $0 == $1 }.count
        let oldTail = Array(oldLines.dropFirst(commonPrefixCount))
        let newTail = Array(newLines.dropFirst(commonPrefixCount))
        for line in oldTail.prefix(80) {
            out.append("-\(line)")
        }
        for line in newTail.prefix(80) {
            out.append("+\(line)")
        }
        return out.joined(separator: "\n")
    }

    private static let canonicalToolNames: Set<String> = [
        "agent", "apply_patch", "attempt_completion", "bash", "codebase_search", "command_execution", "create_file",
        "debug_clean", "debug_context", "debug_hypothesize", "debug_log", "debug_mark",
        "debug_panel", "debug_query", "debug_session",
        "delete_file", "diagnostics", "edit", "fetch_file", "file_outline",
        "file_read", "find_and_replace_all", "find_files", "find_references", "find_symbol", "glob",
        "grep", "instant_grep", "list_dir", "list_symbols", "mcp", "mcp_call", "mcp_describe_tool",
        "mcp_health", "mcp_list_servers", "mcp_list_tools", "mcp_reconnect",
        "mermaid_render", "multi_edit",
        "multiedit", "notebook_edit", "notebook_read", "notebook_write", "notebookread", "parallel_apply",
        "policy_ack",
        "read", "read_file", "read_lints", "read_range", "regex_replace", "rename_symbol", "rg",
        "run_agent", "search", "search_symbols", "semantic_search", "skill", "str_replace", "sub_agent",
        "subagent", "todo_write", "todo_read", "undo_edit", "web_fetch", "web_search", "write", "write_file",
        // IDE state tools (mode activation, task panel, swarm)
        "activate_plan_mode", "activate_debug_mode", "show_task_panel", "invoke_swarm",
    ]

    private static let canonicalToolAliases: [String: String] = [
        "applypatch": "apply_patch",
        "codebasesearch": "codebase_search",
        "debugcontext": "debug_context",
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
        "todowrite": "todo_write",
        "todoread": "todo_read",
        "webfetch": "web_fetch",
        "websearch": "web_search",
        "write_stdin": "bash",
        "writefile": "write_file",
    ]

    static func normalizeToolIdentifier(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var normalized = trimmed
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()

        // Strip MCP server tool prefix (e.g. "coderide_todo_write" → "todo_write")
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

    private static func expandedPayload(_ payload: [String: Any]) -> [String: Any] {
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

    private static func decodeJSONObjectString(_ raw: String) -> [String: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    // MARK: - Private mapping

    private static func isCommandTool(tool: String, payload: [String: Any], typeHint: String) -> Bool {
        if tool == "bash" || tool == "command_execution" {
            return true
        }
        if typeHint.contains("command") || typeHint.contains("bash") {
            return true
        }
        return firstString(in: payload, keys: ["command", "command_line", "cmd"]) != nil
    }

    private static func isReadTool(_ tool: String) -> Bool {
        [
            "read", "read_file", "notebookread", "notebook_read", "read_range",
            "file_read", "fetch_file",
        ].contains(tool)
    }

    private static func isFileChangeTool(_ tool: String, typeHint: String) -> Bool {
        if [
            "edit", "write", "write_file", "multiedit", "multi_edit", "create_file", "delete_file",
            "str_replace", "regex_replace", "parallel_apply", "apply_patch", "rename_symbol",
            "find_and_replace_all", "undo_edit", "notebook_edit", "notebook_write",
        ].contains(tool) {
            return true
        }
        return typeHint.contains("file_change") || typeHint.contains("edit") || typeHint.contains("write")
    }

    private static func isSearchTool(_ tool: String) -> Bool {
        [
            "grep", "search", "instant_grep", "rg", "glob", "ls", "list_dir", "find_files",
        ].contains(tool)
    }

    private static func isSemanticTool(_ tool: String) -> Bool {
        [
            "semantic_search", "codebase_search", "find_symbol", "find_references",
            "file_outline", "list_symbols",
        ].contains(tool)
    }

    private static func isMCPTool(_ tool: String, payload: [String: Any]) -> Bool {
        if tool.hasPrefix("mcp_") || tool == "mcp" || tool == "mcp_call" {
            return true
        }
        if firstString(in: payload, keys: ["mcp_tool", "mcp_server", "server_id", "server"]) != nil {
            return true
        }
        return false
    }

    private static func isWebSearchTool(_ tool: String, payload _: [String: Any]) -> Bool {
        tool.hasPrefix("web_search")
    }

    private static func isWebFetchTool(_ tool: String, payload _: [String: Any]) -> Bool {
        tool.hasPrefix("web_fetch")
    }

    private static func isSkillTool(_ tool: String) -> Bool {
        tool == "skill" || tool.hasPrefix("skill_")
    }

    private static func isTodoTool(_ tool: String) -> Bool {
        tool == "todo_write" || tool == "todo_read"
    }

    private static func isIDEStateTool(_ tool: String) -> Bool {
        [
            "debug_panel", "policy_ack", "mermaid_render",
            "activate_plan_mode", "activate_debug_mode",
            "show_task_panel", "invoke_swarm",
        ].contains(tool)
    }

    private static func isAgentTool(_ tool: String) -> Bool {
        ["task", "sub_agent", "subagent", "agent", "run_agent"].contains(tool)
    }

    private static func mapCommand(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let command = firstString(in: payload, keys: ["command", "command_line", "cmd"]) ?? ""
        let titlePrefix = rawTool.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Bash" : rawTool
        let title = "\(titlePrefix) • \(String(command.prefix(50)))\(command.count > 50 ? "..." : "")"
        var mapped: [String: String] = [
            "title": title,
            "detail": command,
            "command": command,
            "tool": normalizeToolIdentifier(rawTool),
        ]
        if let cwd = firstString(in: payload, keys: ["cwd", "working_directory", "workdir"]), !cwd.isEmpty {
            mapped["cwd"] = cwd
        }
        if let output = firstString(in: payload, keys: ["output", "result", "stdout", "content", "message"]), !output.isEmpty {
            mapped["output"] = String(output.prefix(6_000))
        }
        if let stderr = firstString(in: payload, keys: ["stderr", "error", "error_message"]), !stderr.isEmpty {
            mapped["stderr"] = String(stderr.prefix(3_000))
        }
        return ("command_execution", mapped)
    }

    private static func mapRead(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let path = firstString(in: payload, keys: ["path", "file_path", "file", "target_path", "relative_path"]) ?? ""
        let fallbackName = rawTool.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Read" : rawTool
        var mapped: [String: String] = [
            "title": path.isEmpty ? fallbackName : "Read • \((path as NSString).lastPathComponent)",
            "detail": path.isEmpty ? fallbackName : path,
            "tool": normalizeToolIdentifier(rawTool),
        ]
        if !path.isEmpty {
            mapped["path"] = path
            mapped["file"] = path
            mapped["count"] = "1"
            mapped["files"] = path
        }
        if let out = firstString(in: payload, keys: ["content", "output", "result", "text"]), !out.isEmpty {
            mapped["output"] = String(out.prefix(6_000))
        }
        return ("read_batch_completed", mapped)
    }

    private static func mapFileChange(
        tool rawTool: String,
        payload: [String: Any],
        typeHint: String
    ) -> (type: String, payload: [String: String]) {
        let path = firstString(
            in: payload,
            keys: ["path", "file_path", "file", "target_path", "relative_path"]
        ) ?? "file"
        let normalizedTool = normalizeToolIdentifier(rawTool)
        let changeType = firstString(
            in: payload,
            keys: ["change_type", "operation", "action", "edit_type"]
        ) ?? (normalizedTool.isEmpty ? typeHint : normalizedTool)
        var mapped: [String: String] = [
            "title": fileChangeTitle(path: path, changeType: changeType),
            "detail": path,
            "path": path,
            "file": path,
            "tool": normalizedTool,
            "change_type": changeType,
        ]
        if let added = firstInt(in: payload, keys: ["additions", "lines_added", "linesAdded", "insertions"]) {
            mapped["linesAdded"] = "\(added)"
        }
        if let removed = firstInt(in: payload, keys: ["deletions", "lines_removed", "linesRemoved", "deletions_count"]) {
            mapped["linesRemoved"] = "\(removed)"
        }
        if let oldText = firstString(in: payload, keys: ["old_string"]), !oldText.isEmpty {
            let newText = firstString(in: payload, keys: ["new_string", "contents", "content"]) ?? ""
            mapped["diffPreview"] = String(buildDiffPreview(old: oldText, new: newText).prefix(12_000))
        } else if let diff = firstString(in: payload, keys: ["diffPreview", "diff", "patch", "unified_diff", "changes_preview"]), !diff.isEmpty {
            mapped["diffPreview"] = String(diff.prefix(12_000))
        }
        return ("file_change", mapped)
    }

    private static func mapSearch(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let normalized = normalizeToolIdentifier(rawTool)
        let query = firstString(in: payload, keys: ["query", "pattern", "search", "needle"]) ?? ""
        let scope = firstString(in: payload, keys: ["pathScope", "scope", "path", "directory", "cwd"]) ?? "."
        let title = query.isEmpty
            ? "Search • \(rawTool)"
            : "Search • \(String(query.prefix(80)))"
        var mapped: [String: String] = [
            "title": title,
            "detail": query.isEmpty ? scope : query,
            "tool": normalized,
        ]
        if !query.isEmpty { mapped["query"] = query }
        if !scope.isEmpty { mapped["pathScope"] = scope }
        if let output = firstString(in: payload, keys: ["output", "result", "content"]), !output.isEmpty {
            mapped["output"] = String(output.prefix(6_000))
        }
        if let matches = firstInt(in: payload, keys: ["matchesCount", "match_count", "count"]), matches >= 0 {
            mapped["matchesCount"] = "\(matches)"
        }
        if normalized == "grep" || normalized == "rg" || normalized == "instant_grep" || !query.isEmpty {
            if mapped["query"] == nil {
                mapped["query"] = "(query)"
            }
            return ("instant_grep", mapped)
        }
        return ("search", mapped)
    }

    private static func mapSemantic(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let query = firstString(in: payload, keys: ["query", "search", "prompt"]) ?? ""
        let title = query.isEmpty ? "semantic_search" : "semantic_search • \(String(query.prefix(80)))"
        var mapped: [String: String] = [
            "title": title,
            "detail": query,
            "tool": normalizeToolIdentifier(rawTool),
        ]
        if !query.isEmpty { mapped["query"] = query }
        if let output = firstString(in: payload, keys: ["output", "result", "content"]), !output.isEmpty {
            mapped["output"] = String(output.prefix(6_000))
        }
        return ("semantic_search", mapped)
    }

    /// When an MCP tool call's underlying tool is an IDE state tool (todo/plan),
    /// remap it to the native event type so the EventNormalizer → UI pipeline handles it.
    private static func remapMCPIDEStateTool(tool _: String, payload: [String: Any]) -> (type: String, payload: [String: String])? {
        // Extract the actual MCP tool name (e.g. "coderide_todo_write")
        let mcpTool = firstString(in: payload, keys: ["mcp_tool", "tool_name"]) ?? ""
        let normalizedMCP = normalizeToolIdentifier(mcpTool)

        if normalizedMCP == "todo_write" || normalizedMCP == "todo_read" {
            return mapTodo(tool: normalizedMCP, payload: payload)
        }
        if normalizedMCP == "plan_step_update" || normalizedMCP == "plan_step" {
            var mapped: [String: String] = [:]
            if let stepId = firstString(in: payload, keys: ["step_id", "stepId"]) { mapped["step_id"] = stepId }
            if let status = firstString(in: payload, keys: ["status"]) { mapped["status"] = status }
            if let title = firstString(in: payload, keys: ["title"]) { mapped["title"] = title }
            return ("plan_step_update", mapped)
        }
        if isIDEStateTool(normalizedMCP) {
            return mapIDEState(tool: normalizedMCP, payload: payload)
        }
        return nil
    }

    private static func mapMCP(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let normalizedTool = normalizeToolIdentifier(rawTool)
        let mcpTool = firstString(in: payload, keys: ["mcp_tool", "tool_name", "tool"]) ?? ""
        let mcpServer = firstString(in: payload, keys: ["mcp_server", "server_id", "server"]) ?? ""
        let title: String = {
            switch normalizedTool {
            case "mcp_list_servers":
                return "MCP discovery • servers"
            case "mcp_list_tools":
                return "MCP discovery • tools"
            case "mcp_describe_tool":
                return "MCP inspect • \(mcpTool.isEmpty ? "tool" : mcpTool)"
            case "mcp_health":
                return "MCP health check"
            case "mcp_reconnect":
                return "MCP reconnect • \(mcpServer.isEmpty ? "server" : mcpServer)"
            default:
                var target = mcpTool.isEmpty ? rawTool : mcpTool
                if target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    target = "tool"
                }
                if !mcpServer.isEmpty {
                    return "MCP call • \(mcpServer)/\(target)"
                }
                return "MCP call • \(target)"
            }
        }()

        var mapped: [String: String] = [
            "title": title,
            "detail": firstString(in: payload, keys: ["detail", "query", "arguments", "args"]) ?? "",
            "tool": rawTool
        ]
        if !mcpTool.isEmpty { mapped["mcp_tool"] = mcpTool }
        if !mcpServer.isEmpty {
            mapped["mcp_server"] = mcpServer
            mapped["server_id"] = mcpServer
        }
        if let added = firstInt(in: payload, keys: ["linesAdded", "additions", "insertions", "added"]) {
            mapped["linesAdded"] = "\(max(0, added))"
        }
        if let removed = firstInt(in: payload, keys: ["linesRemoved", "deletions", "removed"]) {
            mapped["linesRemoved"] = "\(max(0, removed))"
        }
        if let output = firstString(in: payload, keys: ["output", "result", "content"]), !output.isEmpty {
            mapped["output"] = String(output.prefix(6_000))
        }
        if mapped["linesAdded"] == nil || mapped["linesRemoved"] == nil {
            let toolForCounters = firstString(in: payload, keys: ["mcp_tool", "tool_name", "tool_raw", "tool"])
                ?? mcpTool
            if let inferred = inferReplacementSummaryLineCounters(payload: payload, toolName: toolForCounters) {
                mapped["linesAdded"] = mapped["linesAdded"] ?? "\(inferred.added)"
                mapped["linesRemoved"] = mapped["linesRemoved"] ?? "\(inferred.removed)"
            }
        }
        return ("mcp_tool_call", mapped)
    }

    private static func mapWebSearch(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
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

    private static func mapWebFetch(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
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

    private static func mapAgent(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let title = payloadTitle(payload, fallback: "Agent task")
        var mapped: [String: String] = [
            "title": title,
            "detail": firstString(in: payload, keys: ["detail", "task", "description"]) ?? "",
            "tool": normalizeToolIdentifier(rawTool),
        ]
        if let swarmId = firstString(in: payload, keys: ["swarm_id", "agent", "role"]), !swarmId.isEmpty {
            mapped["swarm_id"] = swarmId
            mapped["group_id"] = "swarm-\(swarmId)"
        }
        return ("agent", mapped)
    }

    private static func mapSkill(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
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

    private static func mapIDEState(tool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        switch tool {
        case "debug_panel":
            var mapped: [String: String] = [:]
            if let action = firstString(in: payload, keys: ["action"]) { mapped["action"] = action }
            if let phase = firstString(in: payload, keys: ["phase"]) { mapped["phase"] = phase }
            return ("debug_panel_update", mapped)

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
            if let reason = firstString(in: payload, keys: ["reason"]) { mapped["reason"] = reason }
            return ("activate_plan_mode", mapped)

        case "activate_debug_mode":
            var mapped: [String: String] = [:]
            if let reason = firstString(in: payload, keys: ["reason"]) { mapped["reason"] = reason }
            return ("activate_debug_mode", mapped)

        case "show_task_panel":
            return ("coderide_show_task_panel", [:])

        case "invoke_swarm":
            var mapped: [String: String] = [:]
            if let task = firstString(in: payload, keys: ["task"]) { mapped["task"] = task }
            return ("coderide_invoke_swarm", mapped)

        default:
            return ("command_execution", ["title": tool, "tool": tool])
        }
    }

    private static func mapTodo(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        let normalized = normalizeToolIdentifier(rawTool)
        var mapped: [String: String] = [
            "tool": normalized,
        ]

        // Handle the full todos array from TodoWrite tool input.
        // The LLM sends {"todos": [{"content": "...", "status": "...", "activeForm": "..."}, ...]}
        // Serialize the array as JSON so the normalizer can create individual todo items.
        if let todosArray = payload["todos"] as? [[String: Any]], !todosArray.isEmpty {
            if let todosData = try? JSONSerialization.data(withJSONObject: todosArray),
               let todosJson = String(data: todosData, encoding: .utf8) {
                mapped["todos_json"] = todosJson
            }
            // Use first item's content for the display title
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
            // Handle todos passed as JSON string (common from MCP calls)
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

    private static func mapFallback(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
        var mapped: [String: String] = [
            "title": rawTool.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Tool execution" : rawTool,
            "tool": normalizeToolIdentifier(rawTool),
        ]
        if let detail = firstString(in: payload, keys: ["detail", "query", "arguments", "args", "path", "file"]), !detail.isEmpty {
            mapped["detail"] = detail
        }
        if let path = firstString(in: payload, keys: ["path", "file", "file_path"]), !path.isEmpty {
            mapped["path"] = path
            mapped["file"] = path
        }
        if let output = firstString(in: payload, keys: ["output", "result", "content"]), !output.isEmpty {
            mapped["output"] = String(output.prefix(6_000))
        }
        return ("command_execution", mapped)
    }

    private static func payloadTitle(_ payload: [String: Any], fallback: String) -> String {
        let title = firstString(in: payload, keys: ["title"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? fallback : title
    }

    private static func normalizedStatus(fromTool tool: String, fallback: String?) -> String {
        if tool.hasSuffix("_started") { return "started" }
        if tool.hasSuffix("_completed") || tool.hasSuffix("_finished") { return "completed" }
        if tool.hasSuffix("_failed") || tool.hasSuffix("_error") { return "failed" }
        let normalized = normalizeToolIdentifier(fallback ?? "")
        if ["started", "running", "in_progress"].contains(normalized) { return "started" }
        if ["completed", "ok", "success", "done"].contains(normalized) { return "completed" }
        if ["failed", "error", "timeout"].contains(normalized) { return "failed" }
        return "completed"
    }

    private static let replacementSummaryRegex = try! NSRegularExpression(
        pattern: "\\((\\d+)\\s+lines?\\s*(?:->|\u{2192})\\s*(\\d+)\\s+lines?\\)",
        options: [.caseInsensitive]
    )

    private static func inferReplacementSummaryLineCounters(
        payload: [String: Any],
        toolName: String
    ) -> (added: Int, removed: Int)? {
        let normalizedTool = normalizeToolIdentifier(toolName)
        let acceptsSummary = normalizedTool == "str_replace"
            || normalizedTool == "regex_replace"
            || normalizedTool == "find_and_replace_all"
            || normalizedTool == "parallel_apply"
            || normalizedTool == "multi_edit"
            || normalizedTool == "multiedit"
            || normalizedTool == "apply_patch"
            || normalizedTool == "edit"
            || normalizedTool == "write"
            || normalizedTool == "write_file"
            || normalizedTool.contains("replace")
        guard acceptsSummary else { return nil }

        let summary = firstString(in: payload, keys: ["detail", "output", "result", "content"])
            ?? ""
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = replacementSummaryRegex.firstMatch(in: trimmed, options: [], range: range),
              let oldRange = Range(match.range(at: 1), in: trimmed),
              let newRange = Range(match.range(at: 2), in: trimmed),
              let oldLines = Int(trimmed[oldRange]),
              let newLines = Int(trimmed[newRange]) else {
            return nil
        }
        return (added: max(0, newLines), removed: max(0, oldLines))
    }

    private static func intValue(from raw: Any) -> Int? {
        if let i = raw as? Int { return i }
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
}
