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
                let serverTools = try await tools(for: cfg)
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
            return try await tools(for: cfg)
        }

        var all: [MCPToolDescriptor] = []
        for cfg in servers {
            let tools = try await tools(for: cfg)
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

        let target: MCPConfigLoader.DetectedServer
        if let serverId, !serverId.isEmpty {
            guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
                throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
            }
            target = cfg
        } else {
            var matches: [MCPConfigLoader.DetectedServer] = []
            for cfg in servers {
                let tools = try await tools(for: cfg)
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
                    "Ambiguous MCP tool '\(toolName)' found on multiple servers. Specify serverId, one of: \(names)")
            }
            target = matches[0]
        }

        let valueArgs = arguments.reduce(into: [String: Value]()) { partialResult, kv in
            partialResult[kv.key] = parseValue(kv.value)
        }

        let callStartedAt = Date()
        var finalResult: (content: [Tool.Content], isError: Bool?)?
        var attempt = 0
        while true {
            attempt += 1
            var currentSession = try await session(for: target)
            do {
                let callResult = try await withThrowingTaskGroup(of: (content: [Tool.Content], isError: Bool?).self) { group in
                    group.addTask {
                        try await currentSession.client.callTool(name: toolName, arguments: valueArgs)
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(max(1_000, timeoutMs)) * 1_000_000)
                        throw ToolRuntimeError.timeout(tool: "mcp:\(toolName)", ms: timeoutMs)
                    }
                    guard let first = try await group.next() else {
                        throw ToolRuntimeError.transport("MCP call interrupted")
                    }
                    group.cancelAll()
                    return first
                }
                currentSession.lastUsedAt = Date()
                sessions[target.id] = currentSession
                finalResult = callResult
                break
            } catch {
                let category = classifyMCPError(error)
                let canRetry = shouldRetry(error: error, category: category, attempt: attempt)
                let logMessage = "MCP call failed server=\(target.id) tool=\(toolName) attempt=\(attempt) category=\(category.rawValue) retry=\(canRetry) error=\(error.localizedDescription)"
                Self.logger.error("\(logMessage, privacy: .public)")
                guard canRetry else {
                    throw normalizeMCPError(error, category: category, toolName: toolName, timeoutMs: timeoutMs)
                }
                try? await resetSession(target.id)
                try await backoffBeforeRetry(forAttempt: attempt)
            }
        }
        guard let result = finalResult else {
            await callMetrics.record(serverId: target.id, latencyMs: 0, success: false, error: "No result received")
            throw ToolRuntimeError.transport("MCP call interrupted — no result received")
        }
        let latencyMs = max(1, Int(Date().timeIntervalSince(callStartedAt) * 1000))
        let isErr = result.isError ?? false
        await callMetrics.record(serverId: target.id, latencyMs: latencyMs, success: !isErr, error: isErr ? "isError=true" : nil)
        let text = flattenContent(result.content)
        return (
            serverId: target.id,
            serverName: target.name,
            content: text,
            isError: isErr
        )
    }

    public func callToolsBatch(
        calls: [(serverId: String?, toolName: String, arguments: [String: Any])],
        timeoutMs: Int,
        idleTTLSeconds: Int = 300
    ) async -> [(index: Int, serverId: String, serverName: String, content: String, isError: Bool, error: String?)] {
        await evictIdleSessions(idleTTLSeconds: idleTTLSeconds)

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

        let target: MCPConfigLoader.DetectedServer
        if let serverId, !serverId.isEmpty {
            guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
                throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
            }
            target = cfg
        } else {
            var matches: [MCPConfigLoader.DetectedServer] = []
            for cfg in servers {
                let tools = try await tools(for: cfg)
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
                    "Ambiguous MCP tool '\(toolName)' found on multiple servers. Specify serverId, one of: \(names)")
            }
            target = matches[0]
        }

        let valueArgs = arguments.reduce(into: [String: Value]()) { partialResult, kv in
            partialResult[kv.key] = toValue(kv.value)
        }

        let callStartedAt = Date()
        var finalResult: (content: [Tool.Content], isError: Bool?)?
        var attempt = 0
        while true {
            attempt += 1
            var currentSession = try await session(for: target)
            do {
                let callResult = try await withThrowingTaskGroup(of: (content: [Tool.Content], isError: Bool?).self) { group in
                    group.addTask {
                        try await currentSession.client.callTool(name: toolName, arguments: valueArgs)
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(max(1_000, timeoutMs)) * 1_000_000)
                        throw ToolRuntimeError.timeout(tool: "mcp:\(toolName)", ms: timeoutMs)
                    }
                    guard let first = try await group.next() else {
                        throw ToolRuntimeError.transport("MCP call interrupted")
                    }
                    group.cancelAll()
                    return first
                }
                currentSession.lastUsedAt = Date()
                sessions[target.id] = currentSession
                finalResult = callResult
                break
            } catch {
                let category = classifyMCPError(error)
                let canRetry = shouldRetry(error: error, category: category, attempt: attempt)
                Self.logger.error("MCP callRich failed server=\(target.id, privacy: .public) tool=\(toolName, privacy: .public) attempt=\(attempt) category=\(category.rawValue, privacy: .public) retry=\(canRetry) error=\(error.localizedDescription, privacy: .public)")
                guard canRetry else {
                    throw normalizeMCPError(error, category: category, toolName: toolName, timeoutMs: timeoutMs)
                }
                try? await resetSession(target.id)
                try await backoffBeforeRetry(forAttempt: attempt)
            }
        }
        guard let result = finalResult else {
            await callMetrics.record(serverId: target.id, latencyMs: 0, success: false, error: "No result received")
            throw ToolRuntimeError.transport("MCP call interrupted — no result received")
        }
        let latencyMs = max(1, Int(Date().timeIntervalSince(callStartedAt) * 1000))
        let isErr = result.isError ?? false
        await callMetrics.record(serverId: target.id, latencyMs: latencyMs, success: !isErr, error: isErr ? "isError=true" : nil)
        let text = flattenContent(result.content)
        return (
            serverId: target.id,
            serverName: target.name,
            content: text,
            isError: isErr
        )
    }
}
