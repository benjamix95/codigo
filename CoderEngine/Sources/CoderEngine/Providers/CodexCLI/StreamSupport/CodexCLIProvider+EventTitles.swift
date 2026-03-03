import Foundation

extension CodexCLIProvider {
    static func titleForType(_ type: String, item: [String: Any]) -> String {
        switch type {
        case "file_change":
            var payload: [String: String] = [:]
            if let path = firstString(
                in: item,
                keys: ["path", "file_path", "file", "target_path", "relative_path"]
            ) {
                payload["path"] = path
            }
            if let changeType = firstString(
                in: item,
                keys: ["change_type", "operation", "action", "edit_type", "tool", "name"]
            ) {
                payload["change_type"] = changeType
            }
            return fileChangeTitle(from: payload)
        case "command_execution":
            let cmd = (item["command"] as? String) ?? (item["command_line"] as? String) ?? "command"
            return "Bash • \(String(cmd.prefix(50)))..."
        case "mcp_tool_call":
            return mcpEventTitle(from: item)
        case "web_search":
            return "Search"
        case "web_fetch":
            return "Fetch"
        default:
            return type
        }
    }

    static func detailForType(_ type: String, item: [String: Any]) -> String {
        switch type {
        case "file_change":
            return firstString(
                in: item,
                keys: ["path", "file_path", "file", "target_path", "relative_path"]
            ) ?? ""
        case "command_execution":
            return (item["command"] as? String) ?? (item["command_line"] as? String) ?? ""
        case "mcp_tool_call":
            return mcpEventDetail(from: item)
        case "web_search":
            return (item["query"] as? String) ?? ""
        case "web_fetch":
            return (item["url"] as? String) ?? ""
        default:
            return ""
        }
    }

    static func fileChangeTitle(from payload: [String: String]) -> String {
        let path = (payload["path"] ?? payload["file"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let basename = path.isEmpty ? "file" : (path as NSString).lastPathComponent
        let normalized = (payload["change_type"] ?? payload["operation"] ?? payload["action"] ?? payload["edit_type"] ?? payload["tool"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let label: String
        if normalized.contains("create")
            || normalized == "a"
            || normalized == "add"
            || normalized == "added"
            || normalized == "create_file"
        {
            label = "Created"
        } else if normalized.contains("delete")
            || normalized.contains("remove")
            || normalized == "d"
            || normalized == "deleted"
        {
            label = "Deleted"
        } else {
            label = "Edited"
        }

        if basename.isEmpty || basename == "file" {
            return "\(label) file"
        }
        return "\(label) \(basename)"
    }

    static func mcpEventTitle(from item: [String: Any]) -> String {
        let rawTool = firstString(in: item, keys: ["tool", "name"]) ?? ""
        let tool = rawTool.lowercased()
        let server = (firstString(in: item, keys: ["mcp_server", "server_id", "server"]) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mcpTool = (firstString(in: item, keys: ["mcp_tool", "tool_name"]) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch tool {
        case "mcp_list_servers":
            return "MCP discovery • servers"
        case "mcp_list_tools":
            return "MCP discovery • tools"
        case "mcp_describe_tool":
            return "MCP inspect • \(mcpTool.isEmpty ? "tool" : mcpTool)"
        case "mcp_health":
            return "MCP health check"
        case "mcp_reconnect":
            return "MCP reconnect • \(server.isEmpty ? "server" : server)"
        default:
            if !mcpTool.isEmpty || !server.isEmpty || tool.hasPrefix("mcp") {
                var target = !mcpTool.isEmpty ? mcpTool : rawTool
                if target.isEmpty { target = "tool" }
                if !server.isEmpty {
                    return "MCP call • \(server)/\(target)"
                }
                return "MCP call • \(target)"
            }
            return rawTool.isEmpty ? "MCP operation" : rawTool
        }
    }

    static func mcpEventDetail(from item: [String: Any]) -> String {
        let detail = firstString(in: item, keys: ["detail", "query", "arguments"]) ?? ""
        if !detail.isEmpty {
            return detail
        }
        let output = firstString(in: item, keys: ["output", "result", "message", "content", "text"]) ?? ""
        return String(output.prefix(160))
    }
}
