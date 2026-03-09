import Foundation
import MCP

extension MCPSessionManager {
    public func health(serverId: String? = nil) async -> [String: String] {
        let servers = resolveServers()
        if let serverId, !serverId.isEmpty {
            guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
                return [:]
            }
            return [cfg.id: await healthForServer(cfg)]
        }
        var out: [String: String] = [:]
        for cfg in servers {
            out[cfg.id] = await healthForServer(cfg)
        }
        return out
    }

    public func listServers() -> [(id: String, name: String, source: String)] {
        resolveServers().map { ($0.id, $0.name, $0.source) }
    }

    public func reconnect(serverId: String) async throws {
        let servers = resolveServers()
        guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
            throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
        }
        try await resetSession(cfg.id)
        invalidateNativeToolRegistry()
        _ = try await session(for: cfg)
    }

    public func restartServer(serverId: String) async throws {
        let servers = resolveServers()
        guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
            throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
        }
        if let existing = sessions[cfg.id] {
            await disposeSession(existing)
            sessions.removeValue(forKey: cfg.id)
        }
        invalidateNativeToolRegistry()
        _ = try await session(for: cfg)
    }

    public func shutdownAll() async {
        for (_, session) in sessions {
            await disposeSession(session)
        }
        sessions.removeAll()
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
        if var existing = sessions[cfg.id] {
            if existing.process.isRunning {
                existing.lastUsedAt = Date()
                sessions[cfg.id] = existing
                return existing
            }
            await disposeSession(existing, waitForExit: false)
            sessions.removeValue(forKey: cfg.id)
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
        var s = try await session(for: cfg)
        if !shouldBypassToolCache(for: cfg), !s.cachedTools.isEmpty {
            if let ts = s.cachedToolsTimestamp, Date().timeIntervalSince(ts) < toolCacheTTL {
                s.lastUsedAt = Date()
                sessions[cfg.id] = s
                return s.cachedTools
            }
        }
        let tools: [Tool]
        do {
            let listed = try await s.client.listTools()
            tools = listed.0
        } catch {
            let category = classifyMCPError(error)
            if shouldRetry(error: error, category: category, attempt: 1) {
                try? await resetSession(cfg.id)
                s = try await session(for: cfg)
                let listed = try await s.client.listTools()
                tools = listed.0
            } else {
                throw normalizeMCPError(error, category: category, toolName: "list_tools", timeoutMs: 30_000)
            }
        }
        let descriptors = tools.map { tool in
            let schemaJSON: String
            let dict = valueToJSONObject(tool.inputSchema)
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                schemaJSON = str
            } else {
                schemaJSON = "{\"type\":\"object\",\"properties\":{}}"
            }
            return MCPToolDescriptor(
                name: tool.name,
                description: tool.description ?? "",
                schema: schemaJSON,
                serverId: cfg.id,
                serverName: cfg.name
            )
        }
        s.cachedTools = descriptors
        s.cachedToolsTimestamp = Date()
        s.lastUsedAt = Date()
        sessions[cfg.id] = s
        return descriptors
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
        for (id, session) in sessions where session.lastUsedAt < cutoff {
            await disposeSession(session, waitForExit: false)
            sessions.removeValue(forKey: id)
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
