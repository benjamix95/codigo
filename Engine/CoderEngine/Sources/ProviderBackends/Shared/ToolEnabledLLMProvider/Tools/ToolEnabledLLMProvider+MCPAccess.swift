import Foundation

public struct MCPToolInvocationResult: Sendable, Equatable {
    public let serverId: String
    public let serverName: String
    public let content: String
    public let isError: Bool

    public init(
        serverId: String,
        serverName: String,
        content: String,
        isError: Bool
    ) {
        self.serverId = serverId
        self.serverName = serverName
        self.content = content
        self.isError = isError
    }
}

extension ToolEnabledLLMProvider {
    public func callMCPTool(
        serverId: String? = nil,
        toolName: String,
        arguments: [String: Any],
        timeoutMs: Int = 60_000
    ) async throws -> MCPToolInvocationResult {
        guard policy.enableMCP else {
            throw ToolRuntimeError.mcpUnavailable("MCP disabled by policy")
        }

        let result = try await runtime.mcpSessions.callToolRich(
            serverId: serverId,
            toolName: toolName,
            arguments: arguments,
            timeoutMs: timeoutMs
        )
        return MCPToolInvocationResult(
            serverId: result.serverId,
            serverName: result.serverName,
            content: result.content,
            isError: result.isError
        )
    }
}
