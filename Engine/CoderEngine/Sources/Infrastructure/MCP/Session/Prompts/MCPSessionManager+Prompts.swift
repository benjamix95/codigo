import Foundation
import MCP

extension MCPSessionManager {
    public func listPrompts(serverId: String? = nil, idleTTLSeconds: Int = 300) async throws -> [MCPPromptDescriptor] {
        await evictIdleSessions(idleTTLSeconds: idleTTLSeconds)
        let servers = resolveServers()
        guard !servers.isEmpty else { return [] }

        if let serverId, !serverId.isEmpty {
            guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else { return [] }
            return try await rustListPrompts(for: cfg)
        }

        var all: [MCPPromptDescriptor] = []
        for cfg in servers {
            do {
                all.append(contentsOf: try await rustListPrompts(for: cfg))
            } catch {
                Self.logger.warning("Failed to list prompts for \(cfg.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return all
    }

    public func getPrompt(serverId: String? = nil, name: String, arguments: [String: String] = [:], idleTTLSeconds: Int = 300) async throws -> MCPPromptResult {
        await evictIdleSessions(idleTTLSeconds: idleTTLSeconds)
        let servers = resolveServers()
        guard !servers.isEmpty else {
            throw ToolRuntimeError.mcpUnavailable("No MCP server configured")
        }

        let target = try await resolveTargetServerByPrompt(
            serverId: serverId,
            name: name,
            servers: servers
        )
        return try await rustGetPrompt(
            server: target,
            name: name,
            arguments: arguments
        )
    }

    /// Resolve an MCP prompt preserving native argument types.
    public func getPromptRich(
        serverId: String? = nil,
        name: String,
        arguments: [String: Any] = [:],
        idleTTLSeconds: Int = 300
    ) async throws -> MCPPromptResult {
        await evictIdleSessions(idleTTLSeconds: idleTTLSeconds)
        let servers = resolveServers()
        guard !servers.isEmpty else {
            throw ToolRuntimeError.mcpUnavailable("No MCP server configured")
        }

        let target = try await resolveTargetServerByPrompt(
            serverId: serverId,
            name: name,
            servers: servers
        )
        return try await rustGetPrompt(
            server: target,
            name: name,
            arguments: jsonObjectArguments(fromRich: arguments)
        )
    }

    func promptsForServer(_ cfg: MCPConfigLoader.DetectedServer) async throws -> [MCPPromptDescriptor] {
        let s = try await session(for: cfg)
        let result = try await s.client.listPrompts()
        return result.prompts.map { prompt in
            MCPPromptDescriptor(
                name: prompt.name,
                description: prompt.description,
                arguments: (prompt.arguments ?? []).map {
                    MCPPromptArgument(name: $0.name, description: $0.description, required: $0.required ?? false)
                },
                serverId: cfg.id,
                serverName: cfg.name
            )
        }
    }
}
