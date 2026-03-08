import Foundation
import MCP

extension MCPSessionManager {
    public func listPrompts(serverId: String? = nil, idleTTLSeconds: Int = 300) async throws -> [MCPPromptDescriptor] {
        await evictIdleSessions(idleTTLSeconds: idleTTLSeconds)
        let servers = resolveServers()
        guard !servers.isEmpty else { return [] }

        if let serverId, !serverId.isEmpty {
            guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else { return [] }
            return try await promptsForServer(cfg)
        }

        var all: [MCPPromptDescriptor] = []
        for cfg in servers {
            do {
                all.append(contentsOf: try await promptsForServer(cfg))
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

        let target: MCPConfigLoader.DetectedServer
        if let serverId, !serverId.isEmpty {
            guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
                throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
            }
            target = cfg
        } else {
            var matches: [MCPConfigLoader.DetectedServer] = []
            for cfg in servers {
                let prompts = try await promptsForServer(cfg)
                if prompts.contains(where: { $0.name == name }) { matches.append(cfg) }
            }
            target = try MCPSessionManager.requireUniqueServerMatch(
                matches: matches,
                notFoundMessage: "MCP prompt not found: \(name)",
                ambiguityLabel: "MCP prompt '\(name)'"
            )
        }

        let s = try await session(for: target)
        let valueArgs: [String: Value]? = arguments.isEmpty ? nil : arguments.reduce(into: [:]) { $0[$1.key] = .string($1.value) }
        let result = try await s.client.getPrompt(name: name, arguments: valueArgs)
        var messages: [MCPPromptMessage] = []
        for msg in result.messages {
            let content: String
            switch msg.content {
            case .text(let text): content = text
            case .image(let data, let mime): content = "[image \(mime)] \(data.prefix(100))..."
            case .audio(let data, let mime): content = "[audio \(mime)] \(data.prefix(100))..."
            default:
                content = "[resource: \(String(describing: msg.content).prefix(200))]"
            }
            messages.append(MCPPromptMessage(role: msg.role.rawValue, content: content))
        }
        return MCPPromptResult(description: result.description, messages: messages, serverId: target.id, serverName: target.name)
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

        let target: MCPConfigLoader.DetectedServer
        if let serverId, !serverId.isEmpty {
            guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
                throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
            }
            target = cfg
        } else {
            var matches: [MCPConfigLoader.DetectedServer] = []
            for cfg in servers {
                let prompts = try await promptsForServer(cfg)
                if prompts.contains(where: { $0.name == name }) { matches.append(cfg) }
            }
            target = try MCPSessionManager.requireUniqueServerMatch(
                matches: matches,
                notFoundMessage: "MCP prompt not found: \(name)",
                ambiguityLabel: "MCP prompt '\(name)'"
            )
        }

        let s = try await session(for: target)
        let valueArgs: [String: Value]? = arguments.isEmpty ? nil : arguments.reduce(into: [:]) { partialResult, kv in
            partialResult[kv.key] = toValue(kv.value)
        }
        let result = try await s.client.getPrompt(name: name, arguments: valueArgs)
        var messages: [MCPPromptMessage] = []
        for msg in result.messages {
            let content: String
            switch msg.content {
            case .text(let text): content = text
            case .image(let data, let mime): content = "[image \(mime)] \(data.prefix(100))..."
            case .audio(let data, let mime): content = "[audio \(mime)] \(data.prefix(100))..."
            default:
                content = "[resource: \(String(describing: msg.content).prefix(200))]"
            }
            messages.append(MCPPromptMessage(role: msg.role.rawValue, content: content))
        }
        return MCPPromptResult(description: result.description, messages: messages, serverId: target.id, serverName: target.name)
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
