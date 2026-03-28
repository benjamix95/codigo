import Foundation

extension ToolEnabledLLMProvider {
    /// Generates the system prompt section listing all natively-registered MCP tools, grouped by server.
    var mcpNativeToolsPromptSection: String {
        let registry = MCPNativeToolRegistry.shared
        let entries = registry.entries
        guard !entries.isEmpty else {
            return "No MCP tools currently available. Use `mcp_list_servers` and `mcp_list_tools` to discover tools at runtime."
        }

        let routing = registry.routing
        var serverTools: [String: [(functionName: String, entry: ToolSchemaEntry)]] = [:]
        for entry in entries {
            let serverName: String
            if let route = routing[entry.name] {
                serverName = route.serverId
            } else {
                serverName = "unknown"
            }
            serverTools[serverName, default: []].append((functionName: entry.name, entry: entry))
        }

        var lines: [String] = []
        lines.append("**Available MCP tools** (call directly by function name):")
        for (server, tools) in serverTools.sorted(by: { $0.key < $1.key }) {
            lines.append("")
            let displayServer = server.components(separatedBy: "|").last ?? server
            lines.append("Server: **\(displayServer)**")
            for tool in tools {
                let params = tool.entry.required.isEmpty
                    ? ""
                    : " Args: \(tool.entry.required.map { "`\($0)`" }.joined(separator: ", "))."
                let desc = tool.entry.description
                    .replacingOccurrences(of: "[\(displayServer)] ", with: "")
                    .replacingOccurrences(of: "[\(server)] ", with: "")
                lines.append("- **\(tool.functionName)** — \(desc)\(params)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
