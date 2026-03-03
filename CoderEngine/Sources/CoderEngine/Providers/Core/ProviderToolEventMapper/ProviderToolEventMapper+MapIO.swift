import Foundation

extension ProviderToolEventMapper {
    static func mapCommand(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
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

    static func mapRead(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
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

    static func mapFileChange(
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

    static func mapSearch(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
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
        if mapped["matchesCount"] == nil,
           normalized == "glob",
           let output = mapped["output"], !output.isEmpty {
            let files = output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            mapped["matchesCount"] = "\(files.count)"
        }
        if normalized == "grep" || normalized == "rg" || normalized == "instant_grep" || !query.isEmpty {
            if mapped["query"] == nil {
                mapped["query"] = "(query)"
            }
            return ("instant_grep", mapped)
        }
        return ("search", mapped)
    }

    static func mapSemantic(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
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

    static func mapFallback(tool rawTool: String, payload: [String: Any]) -> (type: String, payload: [String: String]) {
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
}
