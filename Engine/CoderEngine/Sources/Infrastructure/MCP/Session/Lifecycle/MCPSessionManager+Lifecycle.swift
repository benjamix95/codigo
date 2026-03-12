import Foundation
import MCP

extension MCPSessionManager {
    public func health(serverId: String? = nil) async -> [String: String] {
        let servers = resolveServers()
        guard !servers.isEmpty else { return [:] }

        let targets: [MCPConfigLoader.DetectedServer]
        if let serverId, !serverId.isEmpty {
            guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
                return [:]
            }
            targets = [cfg]
        } else {
            targets = servers
        }

        do {
            return try await rustHealthStates(for: targets)
        } catch {
            var fallback: [String: String] = [:]
            for cfg in targets {
                fallback[cfg.id] = await healthForServer(cfg)
            }
            return fallback
        }
    }

    public func listServers() -> [(id: String, name: String, source: String)] {
        resolveServers().map { ($0.id, $0.name, $0.source) }
    }

    public func reconnect(serverId: String) async throws {
        let servers = resolveServers()
        guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
            throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
        }
        try await resetSession(cfg.id, waitForExit: true)
        invalidateNativeToolRegistry()
        try await rustReconnect(server: cfg)
    }

    public func restartServer(serverId: String) async throws {
        let servers = resolveServers()
        guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
            throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
        }
        try await resetSession(cfg.id, waitForExit: true)
        invalidateNativeToolRegistry()
        try await rustRestart(server: cfg)
    }

    public func shutdownAll() async {
        try? await rustShutdownAllServers()
        let storedSessions = Array(sessions.values)
        sessions.removeAll()
        for session in storedSessions {
            await awaitSessionTeardownIfNeeded(for: session.serverId)
            await disposeSession(session)
        }
    }

    static func defaultResolveServers() -> [MCPConfigLoader.DetectedServer] {
        let disabledIds = MCPConfigLoader.loadDisabledServerIDs()
        var detected = MCPConfigLoader.loadDetectedServers()
            .filter { server in
                if disabledIds.contains(server.id) { return false }
                if let legacyID = server.legacyID, disabledIds.contains(legacyID) { return false }
                return true
            }
        let manual = MCPConfigLoader.loadManualServers()
            .filter(\.enabled)
            .map {
                MCPConfigLoader.DetectedServer(
                    id: "manual-\($0.id.uuidString.lowercased())",
                    identity: MCPServerIdentity.make(
                        source: "manual",
                        name: $0.name,
                        origin: "manual",
                        sourcePath: MCPConfigLoader.localMCPConfigPath.path
                    ),
                    legacyID: nil,
                    name: $0.name,
                    command: $0.command,
                    args: $0.args,
                    env: $0.env,
                    source: "Manual"
                )
            }
        detected.append(contentsOf: manual)
        return detected
    }

    public func resolveServers() -> [MCPConfigLoader.DetectedServer] {
        serverResolver()
            .filter { !$0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public func session(for cfg: MCPConfigLoader.DetectedServer) async throws -> MCPServerSession {
        await awaitSessionTeardownIfNeeded(for: cfg.id)
        if var existing = sessions[cfg.id] {
            if existing.process.isRunning {
                existing.lastUsedAt = Date()
                sessions[cfg.id] = existing
                return existing
            }
            sessions.removeValue(forKey: cfg.id)
            await disposeSession(existing, waitForExit: false)
        }

        let (transport, process, resources) = try await MCPTransportFactory.connectToProcess(
            command: cfg.command,
            arguments: cfg.args,
            workingDirectory: nil,
            environment: cfg.env,
            serverLabel: cfg.id
        )
        let client = Client(
            name: "codigo-mcp-client",
            version: "1.0.0",
            configuration: .default
        )
        _ = try await client.connect(transport: transport)

        let built = MCPServerSession(
            serverId: cfg.id,
            serverName: cfg.name,
            client: client,
            transport: transport,
            process: process,
            transportResources: resources,
            lastUsedAt: Date(),
            cachedTools: [],
            cachedToolsTimestamp: nil
        )
        sessions[cfg.id] = built
        return built
    }

    public func tools(for cfg: MCPConfigLoader.DetectedServer) async throws -> [MCPToolDescriptor] {
        try await rustToolDescriptors(for: cfg)
    }

    static func requireUniqueServerMatch(
        matches: [MCPConfigLoader.DetectedServer],
        notFoundMessage: String,
        ambiguityLabel: String
    ) throws -> MCPConfigLoader.DetectedServer {
        guard let first = matches.first else {
            throw ToolRuntimeError.mcpUnavailable(notFoundMessage)
        }
        if matches.count > 1 {
            let names = matches.map(\.name).joined(separator: ", ")
            throw ToolRuntimeError.validation(
                "Ambiguous \(ambiguityLabel) found on multiple servers. Specify serverId, one of: \(names)")
        }
        return first
    }

    public func evictIdleSessions(idleTTLSeconds: Int) async {
        guard idleTTLSeconds > 0 else { return }
        let cutoff = Date().addingTimeInterval(TimeInterval(-idleTTLSeconds))
        let expiredSessionIds = sessions.compactMap { id, session in
            session.lastUsedAt < cutoff ? id : nil
        }
        for id in expiredSessionIds {
            await awaitSessionTeardownIfNeeded(for: id)
            guard let session = sessions.removeValue(forKey: id) else { continue }
            await disposeSession(session, waitForExit: false)
        }
    }

    func invalidateNativeToolRegistry() {
        MCPNativeToolRegistry.shared.clear()
    }

    func shouldBypassToolCache(for cfg: MCPConfigLoader.DetectedServer) -> Bool {
        let normalizedId = cfg.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = cfg.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCommand = cfg.command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedId == "coderide" || normalizedName == "coderide" || normalizedName == "coderide-tools" {
            return true
        }
        return normalizedCommand.contains("coderide-mcp-server")
    }
}
