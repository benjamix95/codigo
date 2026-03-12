import Foundation
import MCP

extension MCPSessionManager {
    public func listResources(serverId: String? = nil, idleTTLSeconds: Int = 300) async throws -> [MCPResourceDescriptor] {
        await evictIdleSessions(idleTTLSeconds: idleTTLSeconds)
        let servers = resolveServers()
        guard !servers.isEmpty else { return [] }

        if let serverId, !serverId.isEmpty {
            guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else { return [] }
            return try await rustListResources(for: cfg)
        }

        var all: [MCPResourceDescriptor] = []
        for cfg in servers {
            do {
                let resources = try await rustListResources(for: cfg)
                all.append(contentsOf: resources)
            } catch {
                Self.logger.warning("Failed to list resources for \(cfg.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return all
    }

    public func readResource(serverId: String? = nil, uri: String, idleTTLSeconds: Int = 300) async throws -> MCPResourceContent {
        await evictIdleSessions(idleTTLSeconds: idleTTLSeconds)
        let servers = resolveServers()
        guard !servers.isEmpty else {
            throw ToolRuntimeError.mcpUnavailable("No MCP server configured")
        }

        let target = try await resolveTargetServerByResource(
            serverId: serverId,
            uri: uri,
            servers: servers
        )
        return try await rustReadResource(server: target, uri: uri)
    }

    public func subscribeResource(serverId: String, uri: String) async throws {
        let servers = resolveServers()
        guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
            throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
        }
        try await rustSubscribeResource(server: cfg, uri: uri)
        resourceSubscriptions[cfg.id, default: []].insert(uri)
    }

    public func unsubscribeResource(serverId: String, uri: String) async {
        let servers = resolveServers()
        guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
            resourceSubscriptions[serverId]?.remove(uri)
            return
        }

        resourceSubscriptions[cfg.id]?.remove(uri)
        let remaining = resourceSubscriptions[cfg.id] ?? []
        if remaining.isEmpty {
            resourceSubscriptions.removeValue(forKey: cfg.id)
        }

        do {
            try await rustUnsubscribeResource(server: cfg, uri: uri)
            for remainingURI in remaining {
                do {
                    try await rustSubscribeResource(server: cfg, uri: remainingURI)
                } catch {
                    Self.logger.warning(
                        "Failed to restore subscription uri=\(remainingURI, privacy: .public) on server=\(cfg.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        } catch {
            Self.logger.warning(
                "Failed to unsubscribe MCP resource uri=\(uri, privacy: .public) on server=\(cfg.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    public func listResourceTemplates(serverId: String? = nil, idleTTLSeconds: Int = 300) async throws -> [MCPResourceTemplate] {
        await evictIdleSessions(idleTTLSeconds: idleTTLSeconds)
        let servers = resolveServers()
        guard !servers.isEmpty else { return [] }

        var targets: [MCPConfigLoader.DetectedServer] = servers
        if let serverId, !serverId.isEmpty {
            targets = servers.filter { $0.id == serverId || $0.name == serverId }
        }

        var all: [MCPResourceTemplate] = []
        for cfg in targets {
            do {
                all.append(contentsOf: try await rustListResourceTemplates(for: cfg))
            } catch {
                Self.logger.warning("Failed to list resource templates for \(cfg.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return all
    }

    func resourcesForServer(_ cfg: MCPConfigLoader.DetectedServer) async throws -> [MCPResourceDescriptor] {
        let s = try await session(for: cfg)
        let result = try await s.client.listResources()
        return result.resources.map {
            MCPResourceDescriptor(uri: $0.uri, name: $0.name, description: $0.description, mimeType: $0.mimeType, serverId: cfg.id, serverName: cfg.name)
        }
    }
}
