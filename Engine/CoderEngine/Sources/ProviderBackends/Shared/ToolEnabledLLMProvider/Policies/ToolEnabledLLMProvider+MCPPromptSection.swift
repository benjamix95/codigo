import Foundation

extension ToolEnabledLLMProvider {
    /// Generates the system prompt section listing all natively-registered MCP tools, grouped by server.
    var mcpNativeToolsPromptSection: String {
        let registry = MCPNativeToolRegistry.shared
        let entries = registry.entries
        guard !entries.isEmpty else {
            return """
            **MCP registry warm-up:** native MCP tools are not hydrated in this round yet.
            - This is NOT permission to fall back to shell workspace discovery.
            - Keep using structured workspace tools (`read`, `read_range`, `grep`, `semantic_search`, `codebase_search`, `find_symbol`, `find_references`, `file_outline`, `list_dir`, `find_files`, `glob`).
            - If the live schema later exposes `coderide_*` aliases, switch to those exact aliases immediately.
            - For SoloCode/CoderIDE workspace sessions, the expected canonical aliases are typically `coderide_read`, `coderide_grep`, `coderide_semantic_search`, `coderide_list_dir`, `coderide_find_files`, and `coderide_glob`.
            """
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
