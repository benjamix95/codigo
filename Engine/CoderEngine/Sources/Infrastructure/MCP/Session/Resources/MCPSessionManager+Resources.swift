import Foundation
import MCP

extension MCPSessionManager {
    public func listResources(serverId: String? = nil, idleTTLSeconds: Int = 300) async throws -> [MCPResourceDescriptor] {
        await evictIdleSessions(idleTTLSeconds: idleTTLSeconds)
        let servers = resolveServers()
        guard !servers.isEmpty else { return [] }

        if let serverId, !serverId.isEmpty {
            guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else { return [] }
            return try await resourcesForServer(cfg)
        }

        var all: [MCPResourceDescriptor] = []
        for cfg in servers {
            do {
                let resources = try await resourcesForServer(cfg)
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

        let target: MCPConfigLoader.DetectedServer
        if let serverId, !serverId.isEmpty {
            guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
                throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
            }
            target = cfg
        } else {
            var matches: [MCPConfigLoader.DetectedServer] = []
            for cfg in servers {
                let resources = try await resourcesForServer(cfg)
                if resources.contains(where: { $0.uri == uri }) {
                    matches.append(cfg)
                }
            }
            target = try MCPSessionManager.requireUniqueServerMatch(
                matches: matches,
                notFoundMessage: "MCP resource not found: \(uri)",
                ambiguityLabel: "MCP resource '\(uri)'"
            )
        }

        let s = try await session(for: target)
        let contents = try await s.client.readResource(uri: uri)
        let first = contents.first
        return MCPResourceContent(
            uri: uri,
            mimeType: first?.mimeType,
            text: first?.text,
            blob: first?.blob,
            serverId: target.id,
            serverName: target.name
        )
    }

    public func subscribeResource(serverId: String, uri: String) async throws {
        let servers = resolveServers()
        guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
            throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
        }
        let s = try await session(for: cfg)
        try await s.client.subscribeToResource(uri: uri)
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

        guard sessions[cfg.id] != nil else { return }

        // The current MCP SDK surface exposes subscribe but no direct unsubscribe.
        // Rebuild the session to guarantee server-side listeners are dropped, then
        // restore only the remaining local subscriptions.
        do {
            try await resetSession(cfg.id)
            if !remaining.isEmpty {
                let refreshed = try await session(for: cfg)
                for remainingURI in remaining {
                    do {
                        try await refreshed.client.subscribeToResource(uri: remainingURI)
                    } catch {
                        Self.logger.warning(
                            "Failed to restore subscription uri=\(remainingURI, privacy: .public) on server=\(cfg.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }
        } catch {
            Self.logger.warning(
                "Failed to rebuild MCP session after unsubscribe uri=\(uri, privacy: .public) on server=\(cfg.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
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
                let s = try await session(for: cfg)
                let result = try await s.client.listResourceTemplates()
                all.append(contentsOf: result.templates.map {
                    MCPResourceTemplate(uriTemplate: $0.uriTemplate, name: $0.name, description: $0.description, mimeType: $0.mimeType, serverId: cfg.id, serverName: cfg.name)
                })
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
