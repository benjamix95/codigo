import Foundation
import MCP

extension MCPSessionManager {
    func rustListServers(
        using servers: [MCPConfigLoader.DetectedServer]
    ) async throws -> [(id: String, name: String, source: String, status: String)] {
        let payload = try await rustLifecycleBackend.request(
            op: "list_servers",
            payload: ["servers": servers.map { MCPLifecycleRustServerConfig(server: $0).jsonObject }]
        ) as MCPLifecycleRustListServersPayload
        return payload.servers.map { ($0.id, $0.name, $0.source, $0.status) }
    }

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

    func rustListResources(
        for server: MCPConfigLoader.DetectedServer
    ) async throws -> [MCPResourceDescriptor] {
        let payload = try await rustLifecycleBackend.listResources(server: server)
        return payload.resources.map { $0.asSessionResourceDescriptor() }
    }

    func rustReadResource(
        server: MCPConfigLoader.DetectedServer,
        uri: String
    ) async throws -> MCPResourceContent {
        let payload = try await rustLifecycleBackend.readResource(server: server, uri: uri)
        guard let first = payload.contents.first else {
            throw ToolRuntimeError.transport("MCP resource response vuota")
        }
        return first.asSessionResourceContent(serverId: server.id, serverName: server.name)
    }

    func rustSubscribeResource(
        server: MCPConfigLoader.DetectedServer,
        uri: String
    ) async throws {
        try await rustLifecycleBackend.subscribeResource(server: server, uri: uri)
    }

    func rustUnsubscribeResource(
        server: MCPConfigLoader.DetectedServer,
        uri: String
    ) async throws {
        try await rustLifecycleBackend.unsubscribeResource(server: server, uri: uri)
    }

    func rustListResourceTemplates(
        for server: MCPConfigLoader.DetectedServer
    ) async throws -> [MCPResourceTemplate] {
        let payload = try await rustLifecycleBackend.listResourceTemplates(server: server)
        return payload.templates.map { $0.asSessionResourceTemplate() }
    }

    func rustListPrompts(
        for server: MCPConfigLoader.DetectedServer
    ) async throws -> [MCPPromptDescriptor] {
        let payload = try await rustLifecycleBackend.listPrompts(server: server)
        return payload.prompts.map { $0.asSessionPromptDescriptor() }
    }

    func rustGetPrompt(
        server: MCPConfigLoader.DetectedServer,
        name: String,
        arguments: [String: Any]
    ) async throws -> MCPPromptResult {
        let payload = try await rustLifecycleBackend.getPrompt(
            server: server,
            name: name,
            arguments: arguments
        )
        return MCPPromptResult(
            description: payload.description,
            messages: payload.messages.map { $0.asSessionPromptMessage() },
            serverId: server.id,
            serverName: server.name
        )
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

    func resolveTargetServerByResource(
        serverId: String?,
        uri: String,
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
            let resources = try await rustListResources(for: cfg)
            if resources.contains(where: { $0.uri == uri }) {
                matches.append(cfg)
            }
        }

        return try MCPSessionManager.requireUniqueServerMatch(
            matches: matches,
            notFoundMessage: "MCP resource not found: \(uri)",
            ambiguityLabel: "MCP resource '\(uri)'"
        )
    }

    func resolveTargetServerByPrompt(
        serverId: String?,
        name: String,
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
            let prompts = try await rustListPrompts(for: cfg)
            if prompts.contains(where: { $0.name == name }) {
                matches.append(cfg)
            }
        }

        return try MCPSessionManager.requireUniqueServerMatch(
            matches: matches,
            notFoundMessage: "MCP prompt not found: \(name)",
            ambiguityLabel: "MCP prompt '\(name)'"
        )
    }
}
