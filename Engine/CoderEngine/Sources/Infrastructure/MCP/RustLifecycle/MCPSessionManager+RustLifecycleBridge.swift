import Foundation
import MCP

extension MCPSessionManager {
    func rustHealthStates(
        for servers: [MCPConfigLoader.DetectedServer]
    ) async throws -> [String: String] {
        try await rustLifecycleBackend.health(servers: servers)
    }

    func rustToolDescriptors(
        for server: MCPConfigLoader.DetectedServer
    ) async throws -> [MCPToolDescriptor] {
        try await rustLifecycleBackend.listTools(server: server)
    }

    func rustReconnect(
        server: MCPConfigLoader.DetectedServer
    ) async throws {
        try await rustLifecycleBackend.reconnect(server: server)
    }

    func rustRestart(
        server: MCPConfigLoader.DetectedServer
    ) async throws {
        try await rustLifecycleBackend.restart(server: server)
    }

    func rustShutdownAllServers() async throws {
        try await rustLifecycleBackend.shutdownAll()
    }

    func rustCallTool(
        server: MCPConfigLoader.DetectedServer,
        toolName: String,
        arguments: [String: Any],
        timeoutMs: Int
    ) async throws -> (serverId: String, serverName: String, content: String, isError: Bool) {
        let callStartedAt = Date()
        var attempt = 0

        while true {
            attempt += 1
            do {
                let payload = try await rustLifecycleBackend.callTool(
                    server: server,
                    toolName: toolName,
                    arguments: arguments
                )
                let latencyMs = max(1, Int(Date().timeIntervalSince(callStartedAt) * 1000))
                await callMetrics.record(
                    serverId: payload.serverId,
                    latencyMs: latencyMs,
                    success: !payload.isError,
                    error: payload.isError ? "isError=true" : nil
                )
                return (
                    serverId: payload.serverId,
                    serverName: payload.serverName,
                    content: payload.content,
                    isError: payload.isError
                )
            } catch {
                let category = classifyMCPError(error)
                let canRetry = shouldRetry(error: error, category: category, attempt: attempt)
                Self.logger.error(
                    "Rust MCP lifecycle call failed server=\(server.id, privacy: .public) tool=\(toolName, privacy: .public) attempt=\(attempt) category=\(category.rawValue, privacy: .public) retry=\(canRetry) error=\(error.localizedDescription, privacy: .public)"
                )
                guard canRetry else {
                    let latencyMs = max(1, Int(Date().timeIntervalSince(callStartedAt) * 1000))
                    await callMetrics.record(
                        serverId: server.id,
                        latencyMs: latencyMs,
                        success: false,
                        error: error.localizedDescription
                    )
                    throw normalizeMCPError(
                        error,
                        category: category,
                        toolName: toolName,
                        timeoutMs: timeoutMs
                    )
                }
                try await backoffBeforeRetry(forAttempt: attempt)
            }
        }
    }

    func resolveTargetServer(
        serverId: String?,
        toolName: String,
        servers: [MCPConfigLoader.DetectedServer]
    ) async throws -> MCPConfigLoader.DetectedServer {
        if let serverId, !serverId.isEmpty {
            guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
                throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
            }
            return cfg
        }

        var matches: [MCPConfigLoader.DetectedServer] = []
        for cfg in servers {
            let tools = try await rustToolDescriptors(for: cfg)
            if tools.contains(where: { $0.name == toolName }) {
                matches.append(cfg)
            }
        }

        if matches.isEmpty {
            throw ToolRuntimeError.mcpUnavailable("MCP tool not found: \(toolName)")
        }
        if matches.count > 1 {
            let names = matches.map(\.name).joined(separator: ", ")
            throw ToolRuntimeError.validation(
                "Ambiguous MCP tool '\(toolName)' found on multiple servers. Specify serverId, one of: \(names)"
            )
        }
        return matches[0]
    }

    func jsonObjectArguments(
        from arguments: [String: String]
    ) -> [String: Any] {
        arguments.reduce(into: [String: Any]()) { partialResult, kv in
            partialResult[kv.key] = valueToJSONObject(parseValue(kv.value))
        }
    }

    func jsonObjectArguments(
        fromRich arguments: [String: Any]
    ) -> [String: Any] {
        arguments.reduce(into: [String: Any]()) { partialResult, kv in
            partialResult[kv.key] = valueToJSONObject(toValue(kv.value))
        }
    }
}
