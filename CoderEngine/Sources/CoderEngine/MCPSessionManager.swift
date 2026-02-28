import Foundation
import MCP
import os

public struct MCPToolDescriptor: Sendable {
    public let name: String
    public let description: String
    /// Proper JSON Schema string (serialized from MCP inputSchema).
    public let schema: String
    public let serverId: String
    public let serverName: String

    /// Parse the JSON schema string into a dictionary for OpenAI function tool registration.
    public var inputSchemaDict: [String: Any]? {
        guard let data = schema.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }

    public var schemaProperties: [String: Any] {
        (inputSchemaDict?["properties"] as? [String: Any]) ?? [:]
    }

    public var schemaRequired: [String] {
        (inputSchemaDict?["required"] as? [String]) ?? []
    }
}

public struct MCPServerSession {
    public let serverId: String
    public let serverName: String
    public let client: Client
    public let transport: StdioTransport
    public let process: Process
    public var lastUsedAt: Date
    public var cachedTools: [MCPToolDescriptor]
    public var cachedToolsTimestamp: Date?
}

public enum MCPErrorCategory: String, Sendable {
    case transport
    case protocolViolation = "protocol"
    case timeout
    case tool
    case user
    case unknown
}

public struct MCPRetryPolicy: Sendable {
    public let maxAttempts: Int
    public let backoffDelaysMs: [Int]
    public let jitterMs: Int

    public static let `default` = MCPRetryPolicy(
        maxAttempts: 2,
        backoffDelaysMs: [150, 350],
        jitterMs: 25
    )

    public init(maxAttempts: Int, backoffDelaysMs: [Int], jitterMs: Int) {
        self.maxAttempts = max(1, maxAttempts)
        self.backoffDelaysMs = backoffDelaysMs.map { max(0, $0) }
        self.jitterMs = max(0, jitterMs)
    }
}

public actor MCPSessionManager {
    private static let logger = Logger(subsystem: "com.codigo.CoderEngine", category: "MCPSessionManager")
    private var sessions: [String: MCPServerSession] = [:]
    private let retryPolicy: MCPRetryPolicy
    /// TTL for cached tool lists before re-fetching (seconds).
    private let toolCacheTTL: TimeInterval = 300

    public init(retryPolicy: MCPRetryPolicy = .default) {
        self.retryPolicy = retryPolicy
    }

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
            throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
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
            throw ToolRuntimeError.mcpUnavailable("No MCP server configured")
        }

        let target: MCPConfigLoader.DetectedServer
        if let serverId, !serverId.isEmpty {
            guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
                throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
            }
            target = cfg
        } else {
            // Auto-route by tool name across all servers
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
            throw ToolRuntimeError.transport("MCP call interrupted — no result received")
        }
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
            lastUsedAt: Date(),
            cachedTools: [],
            cachedToolsTimestamp: nil
        )
        sessions[cfg.id] = built
        return built
    }

    private func tools(for cfg: MCPConfigLoader.DetectedServer) async throws -> [MCPToolDescriptor] {
        var s = try await session(for: cfg)
        if !s.cachedTools.isEmpty {
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

    /// Convert MCP Value to a JSON-compatible Swift object.
    private func valueToJSONObject(_ value: Value) -> Any {
        switch value {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map { valueToJSONObject($0) }
        case .object(let dict):
            return dict.reduce(into: [String: Any]()) { result, kv in
                result[kv.key] = valueToJSONObject(kv.value)
            }
        case .data(_, let data): return data.base64EncodedString()
        @unknown default: return String(describing: value)
        }
    }

    private func flattenContent(_ content: [Tool.Content]) -> String {
        if content.isEmpty { return "(no content)" }
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
            // NSNumber can be bool/int/double — check type ID first
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

    private func classifyMCPError(_ error: Error) -> MCPErrorCategory {
        if let runtimeError = error as? ToolRuntimeError {
            switch runtimeError {
            case .timeout:
                return .timeout
            case .validation:
                return .user
            case .mcpUnavailable:
                return .tool
            case .transport, .sandboxViolation, .budgetExceeded:
                return .transport
            }
        }

        let msg = error.localizedDescription.lowercased()
        if msg.contains("timeout") || msg.contains("timed out") {
            return .timeout
        }
        if msg.contains("invalid params")
            || msg.contains("validation")
            || msg.contains("missing required")
            || msg.contains("bad request")
        {
            return .user
        }
        if msg.contains("tool not found")
            || msg.contains("method not found")
            || msg.contains("unknown tool")
            || msg.contains("unsupported tool")
        {
            return .tool
        }
        if msg.contains("parse error")
            || msg.contains("invalid json")
            || msg.contains("protocol")
        {
            return .protocolViolation
        }
        if msg.contains("broken pipe")
            || msg.contains("connection reset")
            || msg.contains("not connected")
            || msg.contains("transport")
            || msg.contains("econnreset")
        {
            return .transport
        }
        return .unknown
    }

    private func shouldRetry(error: Error, category: MCPErrorCategory, attempt: Int) -> Bool {
        guard attempt < retryPolicy.maxAttempts else { return false }
        switch category {
        case .transport, .timeout, .protocolViolation:
            return true
        case .tool, .user, .unknown:
            return false
        }
    }

    private func backoffBeforeRetry(forAttempt attempt: Int) async throws {
        let index = max(0, attempt - 1)
        let baseDelay = index < retryPolicy.backoffDelaysMs.count
            ? retryPolicy.backoffDelaysMs[index]
            : retryPolicy.backoffDelaysMs.last ?? 0
        let jitter = retryPolicy.jitterMs > 0 ? Int.random(in: 0...retryPolicy.jitterMs) : 0
        let totalDelay = max(0, baseDelay + jitter)
        guard totalDelay > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(totalDelay) * 1_000_000)
    }

    private func normalizeMCPError(
        _ error: Error,
        category: MCPErrorCategory,
        toolName: String,
        timeoutMs: Int
    ) -> Error {
        if let runtimeError = error as? ToolRuntimeError {
            return runtimeError
        }
        switch category {
        case .timeout:
            return ToolRuntimeError.timeout(tool: "mcp:\(toolName)", ms: timeoutMs)
        case .user:
            return ToolRuntimeError.validation(error.localizedDescription)
        case .tool:
            return ToolRuntimeError.mcpUnavailable(error.localizedDescription)
        case .transport, .protocolViolation, .unknown:
            return ToolRuntimeError.transport(error.localizedDescription)
        }
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
