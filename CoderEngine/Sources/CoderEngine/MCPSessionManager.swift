import Foundation
import MCP

public struct MCPToolDescriptor: Sendable {
    public let name: String
    public let description: String
    public let schema: String
    public let serverId: String
}

public struct MCPServerSession {
    public let serverId: String
    public let serverName: String
    public let client: Client
    public let transport: StdioTransport
    public let process: Process
    public var lastUsedAt: Date
    public var cachedTools: [MCPToolDescriptor]
}

public actor MCPSessionManager {
    private var sessions: [String: MCPServerSession] = [:]

    public init() {}

    public func listTools(serverId: String? = nil, idleTTLSeconds: Int = 300) async throws
        -> [MCPToolDescriptor]
    {
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
            throw ToolRuntimeError.mcpUnavailable("Server MCP non trovato: \(serverId)")
        }
        try await resetSession(cfg.id)
        _ = try await session(for: cfg)
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
            throw ToolRuntimeError.mcpUnavailable("Nessun server MCP configurato")
        }

        let target: MCPConfigLoader.DetectedServer
        if let serverId, !serverId.isEmpty {
            guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
                throw ToolRuntimeError.mcpUnavailable("Server MCP non trovato: \(serverId)")
            }
            target = cfg
        } else {
            // Auto routing per nome tool
            var matches: [MCPConfigLoader.DetectedServer] = []
            for cfg in servers {
                let tools = try await tools(for: cfg)
                if tools.contains(where: { $0.name == toolName }) {
                    matches.append(cfg)
                }
            }
            if matches.isEmpty {
                throw ToolRuntimeError.mcpUnavailable("Tool MCP non trovato: \(toolName)")
            }
            if matches.count > 1 {
                let names = matches.map(\.name).joined(separator: ", ")
                throw ToolRuntimeError.validation(
                    "Tool MCP ambiguo '\(toolName)'. Specifica serverId tra: \(names)")
            }
            target = matches[0]
        }

        var currentSession = try await session(for: target)
        let valueArgs = arguments.reduce(into: [String: Value]()) { partialResult, kv in
            partialResult[kv.key] = parseValue(kv.value)
        }

        let result: (content: [Tool.Content], isError: Bool?)
        do {
            result = try await withThrowingTaskGroup(of: (content: [Tool.Content], isError: Bool?).self) { group in
                group.addTask {
                    try await currentSession.client.callTool(name: toolName, arguments: valueArgs)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(max(1_000, timeoutMs)) * 1_000_000)
                    throw ToolRuntimeError.timeout(tool: "mcp:\(toolName)", ms: timeoutMs)
                }
                guard let first = try await group.next() else {
                    throw ToolRuntimeError.transport("MCP call interrotta")
                }
                group.cancelAll()
                return first
            }
        } catch {
            // Retry singolo su errori transienti di trasporto.
            if isTransientMCPError(error) {
                try await resetSession(target.id)
                currentSession = try await session(for: target)
                result = try await currentSession.client.callTool(name: toolName, arguments: valueArgs)
            } else {
                throw error
            }
        }

        currentSession.lastUsedAt = Date()
        sessions[target.id] = currentSession
        let text = flattenContent(result.content)
        return (
            serverId: target.id,
            serverName: target.name,
            content: text,
            isError: result.isError ?? false
        )
    }

    public func shutdownAll() async {
        for (_, session) in sessions {
            await session.client.disconnect()
            if session.process.isRunning {
                session.process.terminate()
            }
        }
        sessions.removeAll()
    }

    private func resolveServers() -> [MCPConfigLoader.DetectedServer] {
        var detected = MCPConfigLoader.loadDetectedServers()
        let manual = MCPConfigLoader.loadManualServers()
            .filter(\.enabled)
            .map {
                MCPConfigLoader.DetectedServer(
                    id: "manual-\($0.id.uuidString.lowercased())",
                    name: $0.name,
                    command: $0.command,
                    args: $0.args,
                    env: $0.env,
                    source: "Manuale"
                )
            }
        detected.append(contentsOf: manual)
        return detected.filter { !$0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func session(for cfg: MCPConfigLoader.DetectedServer) async throws -> MCPServerSession {
        if var existing = sessions[cfg.id] {
            if existing.process.isRunning {
                existing.lastUsedAt = Date()
                sessions[cfg.id] = existing
                return existing
            }
            await existing.client.disconnect()
            sessions.removeValue(forKey: cfg.id)
        }

        let (transport, process) = try await MCPTransportFactory.connectToProcess(
            command: cfg.command,
            arguments: cfg.args,
            workingDirectory: nil,
            environment: cfg.env
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
            lastUsedAt: Date(),
            cachedTools: []
        )
        sessions[cfg.id] = built
        return built
    }

    private func tools(for cfg: MCPConfigLoader.DetectedServer) async throws -> [MCPToolDescriptor] {
        var s = try await session(for: cfg)
        if !s.cachedTools.isEmpty {
            s.lastUsedAt = Date()
            sessions[cfg.id] = s
            return s.cachedTools
        }
        let (tools, _) = try await s.client.listTools()
        let descriptors = tools.map {
            MCPToolDescriptor(
                name: $0.name,
                description: $0.description ?? "",
                schema: String(describing: $0.inputSchema),
                serverId: cfg.id
            )
        }
        s.cachedTools = descriptors
        s.lastUsedAt = Date()
        sessions[cfg.id] = s
        return descriptors
    }

    private func flattenContent(_ content: [Tool.Content]) -> String {
        if content.isEmpty { return "(nessun contenuto)" }
        var chunks: [String] = []
        for item in content {
            switch item {
            case .text(let text):
                if !text.isEmpty { chunks.append(text) }
            case .image(_, let mimeType, _):
                chunks.append("[image \(mimeType)]")
            case .audio(_, let mimeType):
                chunks.append("[audio \(mimeType)]")
            default:
                chunks.append(String(describing: item))
            }
        }
        return chunks.joined(separator: "\n")
    }

    private func parseValue(_ raw: String) -> Value {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .string("") }
        if trimmed == "true" { return .bool(true) }
        if trimmed == "false" { return .bool(false) }
        if trimmed == "null" { return .null }
        if let i = Int(trimmed) { return .int(i) }
        if let d = Double(trimmed), trimmed.contains(".") { return .double(d) }

        if let data = trimmed.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) {
            return toValue(parsed)
        }
        return .string(trimmed)
    }

    private func toValue(_ obj: Any) -> Value {
        switch obj {
        case is NSNull:
            return .null
        case let b as Bool:
            return .bool(b)
        case let i as Int:
            return .int(i)
        case let n as NSNumber:
            // NSNumber può essere bool/int/double
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            if floor(n.doubleValue) == n.doubleValue {
                return .int(n.intValue)
            }
            return .double(n.doubleValue)
        case let s as String:
            return .string(s)
        case let arr as [Any]:
            return .array(arr.map { toValue($0) })
        case let dict as [String: Any]:
            var mapped: [String: Value] = [:]
            for (k, v) in dict {
                mapped[k] = toValue(v)
            }
            return .object(mapped)
        default:
            return .string(String(describing: obj))
        }
    }

    private func isTransientMCPError(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("broken pipe")
            || msg.contains("connection reset")
            || msg.contains("transport")
            || msg.contains("not connected")
    }

    private func healthForServer(_ cfg: MCPConfigLoader.DetectedServer) async -> String {
        do {
            _ = try await tools(for: cfg)
            return "ok"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    private func resetSession(_ id: String) async throws {
        if let existing = sessions[id] {
            await existing.client.disconnect()
            if existing.process.isRunning {
                existing.process.terminate()
            }
            sessions.removeValue(forKey: id)
        }
    }

    private func evictIdleSessions(idleTTLSeconds: Int) async {
        guard idleTTLSeconds > 0 else { return }
        let cutoff = Date().addingTimeInterval(TimeInterval(-idleTTLSeconds))
        for (id, session) in sessions where session.lastUsedAt < cutoff {
            await session.client.disconnect()
            if session.process.isRunning {
                session.process.terminate()
            }
            sessions.removeValue(forKey: id)
        }
    }
}
