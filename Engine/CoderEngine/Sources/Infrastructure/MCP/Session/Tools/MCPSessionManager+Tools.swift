import Foundation
import MCP

extension MCPSessionManager {
    /// Eagerly discover all tools from all configured MCP servers.
    /// Returns the full list of tool descriptors across all servers.
    public func discoverAllTools(idleTTLSeconds: Int = 300) async -> [MCPToolDescriptor] {
        await evictIdleSessions(idleTTLSeconds: idleTTLSeconds)
        let servers = resolveServers()
        var all: [MCPToolDescriptor] = []
        for cfg in servers {
            do {
                let serverTools = try await rustToolDescriptors(for: cfg)
                all.append(contentsOf: serverTools)
            } catch {
                Self.logger.warning("Failed to discover tools for \(cfg.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return all
    }

    public func listTools(serverId: String? = nil, idleTTLSeconds: Int = 300) async throws -> [MCPToolDescriptor] {
        await evictIdleSessions(idleTTLSeconds: idleTTLSeconds)
        let servers = resolveServers()
        guard !servers.isEmpty else { return [] }

        if let serverId, !serverId.isEmpty {
            guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
                return []
            }
            return try await rustToolDescriptors(for: cfg)
        }

        var all: [MCPToolDescriptor] = []
        for cfg in servers {
            let tools = try await rustToolDescriptors(for: cfg)
            all.append(contentsOf: tools)
        }
        return all
    }

    public func describeTool(
        serverId: String? = nil,
        toolName: String
    ) async throws -> MCPToolDescriptor? {
        let all = try await listTools(serverId: serverId)
        return all.first { $0.name == toolName }
    }

    public func callTool(
        serverId: String? = nil,
        toolName: String,
        arguments: [String: String],
        timeoutMs: Int,
        idleTTLSeconds: Int = 300
    ) async throws -> (serverId: String, serverName: String, content: String, isError: Bool) {
        await evictIdleSessions(idleTTLSeconds: idleTTLSeconds)
        let servers = resolveServers()
        guard !servers.isEmpty else {
            throw ToolRuntimeError.mcpUnavailable("No MCP server configured")
        }

        let target = try await resolveTargetServer(
            serverId: serverId,
            toolName: toolName,
            servers: servers
        )
        return try await rustCallTool(
            server: target,
            toolName: toolName,
            arguments: jsonObjectArguments(from: arguments),
            timeoutMs: timeoutMs
        )
    }

    public func callToolsBatch(
        calls: [(serverId: String?, toolName: String, arguments: [String: Any])],
        timeoutMs: Int,
        idleTTLSeconds: Int = 300
    ) async -> [(index: Int, serverId: String, serverName: String, content: String, isError: Bool, error: String?)] {
        _ = timeoutMs
        do {
            return try await rustCallToolsBatch(
                calls: calls,
                idleTTLSeconds: idleTTLSeconds
            )
        } catch {
            return await withTaskGroup(of: (Int, String, String, String, Bool, String?).self) { group in
                for (index, call) in calls.enumerated() {
                    group.addTask {
                        do {
                            let result = try await self.callToolRich(
                                serverId: call.serverId,
                                toolName: call.toolName,
                                arguments: call.arguments,
                                timeoutMs: timeoutMs,
                                idleTTLSeconds: idleTTLSeconds
                            )
                            return (index, result.serverId, result.serverName, result.content, result.isError, nil)
                        } catch {
                            return (index, call.serverId ?? "", "", "", true, error.localizedDescription)
                        }
                    }
                }

                var results: [(index: Int, serverId: String, serverName: String, content: String, isError: Bool, error: String?)] = []
                for await result in group {
                    results.append((index: result.0, serverId: result.1, serverName: result.2, content: result.3, isError: result.4, error: result.5))
                }
                return results.sorted { $0.index < $1.index }
            }
        }
    }

    /// Call an MCP tool with rich (native-typed) arguments.
    /// Unlike the `[String: String]` variant, this preserves arrays, objects, numbers, and booleans.
    public func callToolRich(
        serverId: String? = nil,
        toolName: String,
        arguments: [String: Any],
        timeoutMs: Int,
        idleTTLSeconds: Int = 300
    ) async throws -> (serverId: String, serverName: String, content: String, isError: Bool) {
        await evictIdleSessions(idleTTLSeconds: idleTTLSeconds)
        let servers = resolveServers()
        guard !servers.isEmpty else {
            throw ToolRuntimeError.mcpUnavailable("No MCP server configured")
        }

        let target = try await resolveTargetServer(
            serverId: serverId,
            toolName: toolName,
            servers: servers
        )
        return try await rustCallTool(
            server: target,
            toolName: toolName,
            arguments: jsonObjectArguments(fromRich: arguments),
            timeoutMs: timeoutMs
        )
    }
}
