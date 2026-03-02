import Foundation
import os

extension UnifiedToolRuntime {
    func canFallbackToMCP(toolName: String, call: ToolCall) -> Bool {
        if toolName == "mcp" || toolName == "mcp_call" || toolName.hasPrefix("mcp_") {
            return true
        }
        if isQualifiedMCPToolReference(toolName) {
            return true
        }
        if toolName.hasPrefix("coderide_") {
            return true
        }
        let hasToolArg = call.args["tool"] != nil || call.args["mcp_tool"] != nil
        let hasServerArg = call.args["server"] != nil || call.args["server_id"] != nil || call.args["mcp_server"] != nil
        return hasToolArg && (hasServerArg || toolName == "mcp" || toolName == "mcp_call")
    }

    func resolveMCPServerArg(from args: [String: String]) -> String {
        (args["server"] ?? args["server_id"] ?? args["mcp_server"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isQualifiedMCPToolReference(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return false }
        return isValidMCPIdentifier(parts[0]) && isValidMCPIdentifier(parts[1])
    }

    func isValidMCPIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = #"^[A-Za-z0-9_.:-]{1,128}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    struct MCPInvocation {
        let serverId: String?
        let toolName: String
        let arguments: [String: String]
    }

    static let mcpWrapperKeys: Set<String> = [
        "name", "id", "tool", "mcp_tool", "server", "server_id", "mcp_server", "args"
    ]

    func buildMCPInvocation(
        call: ToolCall,
        fallbackToolName: String? = nil
    ) throws -> MCPInvocation {
        let toolFromArgs = (call.args["tool"] ?? call.args["mcp_tool"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTool = (fallbackToolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedToolRaw = !toolFromArgs.isEmpty ? toolFromArgs : fallbackTool
        guard !requestedToolRaw.isEmpty else {
            throw ToolRuntimeError.validation("Missing MCP tool name")
        }

        let server = (call.args["server"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let serverID = (call.args["server_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let mcpServer = (call.args["mcp_server"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let serverCandidates = [server, serverID, mcpServer].filter { !$0.isEmpty }
        if Set(serverCandidates).count > 1 {
            throw ToolRuntimeError.validation("Conflicting MCP server values in server/server_id/mcp_server")
        }
        let explicitServer = serverCandidates.first

        let parsedServer: String?
        let parsedTool: String
        if requestedToolRaw.contains("/") {
            let parts = requestedToolRaw.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else {
                throw ToolRuntimeError.validation("Ambiguous MCP tool reference '\(requestedToolRaw)'")
            }
            guard isValidMCPIdentifier(parts[0]), isValidMCPIdentifier(parts[1]) else {
                throw ToolRuntimeError.validation("Invalid MCP server/tool identifier in '\(requestedToolRaw)'")
            }
            if let explicitServer, explicitServer != parts[0] {
                throw ToolRuntimeError.validation("Conflicting MCP server between tool reference and server argument")
            }
            parsedServer = parts[0]
            parsedTool = parts[1]
        } else {
            guard isValidMCPIdentifier(requestedToolRaw) else {
                throw ToolRuntimeError.validation("Invalid MCP tool identifier '\(requestedToolRaw)'")
            }
            if let explicitServer, !explicitServer.isEmpty, !isValidMCPIdentifier(explicitServer) {
                throw ToolRuntimeError.validation("Invalid MCP server identifier '\(explicitServer)'")
            }
            parsedServer = explicitServer
            parsedTool = requestedToolRaw
        }

        var mergedArgs: [String: String] = [:]
        let embeddedArgs = parseEmbeddedArgs(call.args["args"])
        for (key, value) in embeddedArgs {
            mergedArgs[key] = value
        }
        for (key, value) in call.args where !Self.mcpWrapperKeys.contains(key) {
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidMCPIdentifier(trimmedKey) else {
                throw ToolRuntimeError.validation("Unsupported MCP argument key '\(key)'")
            }
            mergedArgs[trimmedKey] = value
        }

        return MCPInvocation(serverId: parsedServer, toolName: parsedTool, arguments: mergedArgs)
    }

    public func executeMCP(call: ToolCall, context: ToolExecutionContext) async -> ToolResult {
        await executeMCPCall(call: call, context: context, startDate: Date())
    }

}
