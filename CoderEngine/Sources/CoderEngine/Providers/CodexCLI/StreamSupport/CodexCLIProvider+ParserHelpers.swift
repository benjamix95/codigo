import Foundation

extension CodexCLIProvider {
    static func isToolLikeRawEvent(
        type: String,
        eventType: String,
        item: [String: Any]
    ) -> Bool {
        let normalizedType = ProviderToolEventMapper.normalizeToolIdentifier(type)
        guard !normalizedType.isEmpty else { return false }

        let nonToolTypes: Set<String> = [
            "reasoning",
            "agent_message",
            "assistant_message",
            "user_message",
            "message",
            "text",
            "final_answer",
        ]
        if nonToolTypes.contains(normalizedType) { return false }

        if eventType.contains("tool") || eventType.contains("function_call") {
            return true
        }

        let toolLikeTypes: Set<String> = [
            "tool_call",
            "function_call",
            "tool_result",
            "function_result",
            "command_execution",
            "file_change",
            "mcp_tool_call",
            "skill",
            "skill_invocation",
            "todo_write",
            "todo_read",
            "web_search",
            "web_fetch",
            "instant_grep",
            "search",
            "semantic_search",
            "codebase_search",
            "find_symbol",
            "find_references",
            "file_outline",
            "list_symbols",
            "read",
            "read_range",
            "list_dir",
            "glob",
            "grep",
            "str_replace",
            "edit",
            "write",
            "create_file",
            "delete_file",
            "parallel_apply",
            "rename_symbol",
            "find_files",
            "mcp_call",
            "mcp_list_servers",
            "mcp_list_tools",
            "mcp_describe_tool",
            "mcp_health",
            "mcp_reconnect",
            "index_status",
            "reindex",
            "read_lints",
            "debug_context",
            "diagnostics",
        ]
        if toolLikeTypes.contains(normalizedType) { return true }
        if normalizedType.hasPrefix("mcp_") || normalizedType.hasPrefix("web_") { return true }

        let toolSignalKeys = [
            "tool", "tool_name", "function", "function_name", "mcp_tool", "mcp_server", "server_id",
            "command", "command_line", "cmd", "old_string", "new_string", "query", "pattern",
            "args", "arguments",
        ]
        return firstString(in: item, keys: toolSignalKeys) != nil
    }

    static func normalizedEventType(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    static func firstString(in input: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = input[key] {
                if let stringValue = stringify(value), !stringValue.isEmpty {
                    return stringValue
                }
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
            guard let value = input[key] else { continue }
            if let intValue = intValue(from: value) {
                return intValue
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

    static func intValue(from value: Any) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(trimmed)
        }
        return nil
    }

    static func stringify(_ value: Any) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let arr = value as? [String] { return arr.joined(separator: "\n") }
        if let arr = value as? [[String: Any]] {
            let chunks = arr.compactMap { dict -> String? in
                if let t = dict["text"] as? String { return t }
                if let o = dict["output"] as? String { return o }
                return nil
            }
            if !chunks.isEmpty { return chunks.joined(separator: "\n") }
        }
        if let dict = value as? [String: Any] {
            if let t = dict["text"] as? String { return t }
            if let o = dict["output"] as? String { return o }
            if let e = dict["error"] as? String { return e }
        }
        return nil
    }

    static func containsCompactionSignal(json: [String: Any]) -> Bool {
        if let item = json["item"] as? [String: Any],
           let itemType = item["type"] as? String,
           itemType.lowercased().contains("compaction") {
            return true
        }
        if let type = json["type"] as? String, type.lowercased().contains("compaction") {
            return true
        }
        // Defensive fallback: intercept any text-based payloads that include the keyword.
        let payload = String(describing: json).lowercased()
        return payload.contains("compaction")
    }
}
