import Foundation

enum ProviderToolEventMapper {
    static func map(
        toolName rawToolName: String,
        payload: [String: Any],
        typeHint: String? = nil
    ) -> (type: String, payload: [String: String])? {
        let normalizedTool = normalizeToolIdentifier(rawToolName)
        let normalizedHint = normalizeToolIdentifier(typeHint ?? "")
        let tool = normalizedTool.isEmpty ? normalizedHint : normalizedTool

        if isCommandTool(tool: tool, payload: payload, typeHint: normalizedHint) {
            return mapCommand(tool: rawToolName, payload: payload)
        }
        if isReadTool(tool) {
            return mapRead(tool: rawToolName, payload: payload)
        }
        if isFileChangeTool(tool, typeHint: normalizedHint) {
            return mapFileChange(tool: rawToolName, payload: payload, typeHint: normalizedHint)
        }
        if isSemanticTool(tool) {
            return mapSemantic(tool: rawToolName, payload: payload)
        }
        if isSearchTool(tool) {
            return mapSearch(tool: rawToolName, payload: payload)
        }
        if isMCPTool(tool, payload: payload) {
            return mapMCP(tool: rawToolName, payload: payload)
        }
        if isWebSearchTool(tool, payload: payload) {
            return mapWebSearch(tool: rawToolName, payload: payload)
        }
        if isWebFetchTool(tool, payload: payload) {
            return mapWebFetch(tool: rawToolName, payload: payload)
        }
        if isAgentTool(tool) {
            return mapAgent(tool: rawToolName, payload: payload)
        }
        if !tool.isEmpty {
            return mapFallback(tool: rawToolName, payload: payload)
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

    static func normalizeToolIdentifier(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
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
        if ["edit", "write", "multiedit", "multi_edit", "create_file", "delete_file", "str_replace", "regex_replace", "parallel_apply", "rename_symbol", "find_and_replace_all", "undo_edit"].contains(tool) {
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
        if let output = firstString(in: payload, keys: ["output", "result", "content"]), !output.isEmpty {
            mapped["output"] = String(output.prefix(6_000))
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

    private static func intValue(from raw: Any) -> Int? {
        if let i = raw as? Int { return i }
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
}
