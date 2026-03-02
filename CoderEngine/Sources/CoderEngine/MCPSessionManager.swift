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
    public var connectedAt: Date = Date()
}

// MARK: - MCP Resource Types

public struct MCPResourceDescriptor: Sendable {
    public let uri: String
    public let name: String
    public let description: String?
    public let mimeType: String?
    public let serverId: String
    public let serverName: String
}

public struct MCPResourceContent: Sendable {
    public let uri: String
    public let mimeType: String?
    public let text: String?
    public let blob: String?
    public let serverId: String
    public let serverName: String
}

public struct MCPResourceTemplate: Sendable {
    public let uriTemplate: String
    public let name: String
    public let description: String?
    public let mimeType: String?
    public let serverId: String
    public let serverName: String
}

// MARK: - MCP Prompt Types

public struct MCPPromptDescriptor: Sendable {
    public let name: String
    public let description: String?
    public let arguments: [MCPPromptArgument]
    public let serverId: String
    public let serverName: String
}

public struct MCPPromptArgument: Sendable {
    public let name: String
    public let description: String?
    public let required: Bool
}

public struct MCPPromptResult: Sendable {
    public let description: String?
    public let messages: [MCPPromptMessage]
    public let serverId: String
    public let serverName: String
}

public struct MCPPromptMessage: Sendable {
    public let role: String
    public let content: String
}

// MARK: - MCP Server Capabilities & Metrics

public struct MCPServerCapabilities: Sendable {
    public let supportsTools: Bool
    public let supportsResources: Bool
    public let supportsPrompts: Bool
    public let supportsLogging: Bool
    public let supportsResourceSubscriptions: Bool
}

public struct MCPServerMetrics: Sendable {
    public let serverId: String
    public let serverName: String
    public let status: String
    public let uptimeSeconds: Int
    public let totalCalls: Int
    public let failedCalls: Int
    public let avgLatencyMs: Int
    public let p95LatencyMs: Int
    public let lastError: String?
    public let lastErrorAt: Date?
    public let toolCount: Int
    public let resourceCount: Int
    public let promptCount: Int
    public let capabilities: MCPServerCapabilities
}

// MARK: - MCP Log Types

public struct MCPLogEntry: Sendable {
    public let timestamp: Date
    public let level: String
    public let message: String
    public let serverId: String
    public let serverName: String
    public let logger: String?
}

/// Thread-safe circular buffer for aggregating MCP server logs.
public actor MCPLogStore {
    private var entries: [MCPLogEntry] = []
    private let maxEntries: Int

    public init(maxEntries: Int = 2000) {
        self.maxEntries = maxEntries
    }

    public func append(_ entry: MCPLogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    public func logs(
        serverId: String? = nil,
        severity: String? = nil,
        limit: Int = 100
    ) -> [MCPLogEntry] {
        var filtered = entries
        if let serverId, !serverId.isEmpty {
            filtered = filtered.filter { $0.serverId == serverId }
        }
        if let severity, !severity.isEmpty {
            let levels = severityAndAbove(severity)
            filtered = filtered.filter { levels.contains($0.level.lowercased()) }
        }
        return Array(filtered.suffix(min(limit, filtered.count)))
    }

    public func clear(serverId: String? = nil) {
        if let serverId {
            entries.removeAll { $0.serverId == serverId }
        } else {
            entries.removeAll()
        }
    }

    private func severityAndAbove(_ severity: String) -> Set<String> {
        let ordered = ["debug", "info", "notice", "warning", "error", "critical", "alert", "emergency"]
        guard let idx = ordered.firstIndex(of: severity.lowercased()) else {
            return Set(ordered)
        }
        return Set(ordered[idx...])
    }
}

// MARK: - MCP Call Metrics Tracker

public actor MCPCallMetricsTracker {
    struct ServerStats {
        var totalCalls: Int = 0
        var failedCalls: Int = 0
        var latencies: [Int] = []
        var lastError: String?
        var lastErrorAt: Date?

        mutating func record(latencyMs: Int, success: Bool, error: String? = nil) {
            totalCalls += 1
            latencies.append(latencyMs)
            if latencies.count > 500 { latencies.removeFirst(latencies.count - 500) }
            if !success {
                failedCalls += 1
                lastError = error
                lastErrorAt = Date()
            }
        }

        var avgLatencyMs: Int {
            guard !latencies.isEmpty else { return 0 }
            return latencies.reduce(0, +) / latencies.count
        }

        var p95LatencyMs: Int {
            guard !latencies.isEmpty else { return 0 }
            let sorted = latencies.sorted()
            let idx = Int(Double(sorted.count) * 0.95)
            return sorted[min(idx, sorted.count - 1)]
        }
    }

    private var stats: [String: ServerStats] = [:]

    func record(serverId: String, latencyMs: Int, success: Bool, error: String? = nil) {
        stats[serverId, default: ServerStats()].record(latencyMs: latencyMs, success: success, error: error)
    }

    func metrics(for serverId: String) -> ServerStats {
        stats[serverId] ?? ServerStats()
    }

    func allMetrics() -> [String: ServerStats] {
        stats
    }
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
    private let serverResolver: () -> [MCPConfigLoader.DetectedServer]
    /// TTL for cached tool lists before re-fetching (seconds).
    private let toolCacheTTL: TimeInterval = 300

    public let logStore = MCPLogStore()
    public let callMetrics = MCPCallMetricsTracker()
    private var resourceSubscriptions: [String: Set<String>] = [:]

    public init(
        retryPolicy: MCPRetryPolicy = .default,
        serverResolver: (() -> [MCPConfigLoader.DetectedServer])? = nil
    ) {
        self.retryPolicy = retryPolicy
        self.serverResolver = serverResolver ?? {
            MCPSessionManager.defaultResolveServers()
        }
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

    // MARK: - Resources API

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

    public func readResource(serverId: String? = nil, uri: String, idleTTLSeconds: Int = 300) async throws
        -> MCPResourceContent
    {
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
            target = try Self.requireUniqueServerMatch(
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

    private func resourcesForServer(_ cfg: MCPConfigLoader.DetectedServer) async throws -> [MCPResourceDescriptor] {
        let s = try await session(for: cfg)
        let result = try await s.client.listResources()
        return result.resources.map {
            MCPResourceDescriptor(uri: $0.uri, name: $0.name, description: $0.description, mimeType: $0.mimeType, serverId: cfg.id, serverName: cfg.name)
        }
    }

    // MARK: - Prompts API

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
            target = try Self.requireUniqueServerMatch(
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
            target = try Self.requireUniqueServerMatch(
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

    private func promptsForServer(_ cfg: MCPConfigLoader.DetectedServer) async throws -> [MCPPromptDescriptor] {
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

    // MARK: - Logging API

    /// Set log level on a server via raw JSON-RPC (not all SDK versions expose this natively).
    public func setLogLevel(serverId: String, level: String) async throws {
        let servers = resolveServers()
        guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
            throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
        }
        _ = try await session(for: cfg)
        Self.logger.info("setLogLevel requested for \(cfg.id, privacy: .public) level=\(level, privacy: .public) — stored locally (SDK passthrough not available)")
    }

    // MARK: - Metrics API

    public func serverMetrics(serverId: String? = nil) async -> [MCPServerMetrics] {
        let servers = resolveServers()
        var targets = servers
        if let serverId, !serverId.isEmpty {
            targets = servers.filter { $0.id == serverId || $0.name == serverId }
        }

        var results: [MCPServerMetrics] = []
        for cfg in targets {
            let stats = await callMetrics.metrics(for: cfg.id)
            let status: String
            let toolCount: Int
            let resourceCount: Int
            let promptCount: Int
            var capabilities = MCPServerCapabilities(supportsTools: false, supportsResources: false, supportsPrompts: false, supportsLogging: false, supportsResourceSubscriptions: false)

            if let s = sessions[cfg.id], s.process.isRunning {
                status = stats.failedCalls > 0 && Double(stats.failedCalls) / max(1, Double(stats.totalCalls)) > 0.5 ? "degraded" : "ok"
                toolCount = s.cachedTools.count
                resourceCount = (try? await resourcesForServer(cfg).count) ?? 0
                promptCount = (try? await promptsForServer(cfg).count) ?? 0
                capabilities = MCPServerCapabilities(
                    supportsTools: true,
                    supportsResources: resourceCount > 0,
                    supportsPrompts: promptCount > 0,
                    supportsLogging: true,
                    supportsResourceSubscriptions: !(resourceSubscriptions[cfg.id]?.isEmpty ?? true)
                )
            } else {
                status = "disconnected"
                toolCount = 0
                resourceCount = 0
                promptCount = 0
            }

            let uptime: Int
            if let s = sessions[cfg.id] {
                uptime = Int(Date().timeIntervalSince(s.connectedAt))
            } else {
                uptime = 0
            }

            results.append(MCPServerMetrics(
                serverId: cfg.id,
                serverName: cfg.name,
                status: status,
                uptimeSeconds: uptime,
                totalCalls: stats.totalCalls,
                failedCalls: stats.failedCalls,
                avgLatencyMs: stats.avgLatencyMs,
                p95LatencyMs: stats.p95LatencyMs,
                lastError: stats.lastError,
                lastErrorAt: stats.lastErrorAt,
                toolCount: toolCount,
                resourceCount: resourceCount,
                promptCount: promptCount,
                capabilities: capabilities
            ))
        }
        return results
    }

    // MARK: - Restart Server

    public func restartServer(serverId: String) async throws {
        let servers = resolveServers()
        guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
            throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
        }
        if let existing = sessions[cfg.id] {
            await existing.client.disconnect()
            if existing.process.isRunning {
                existing.process.terminate()
                existing.process.waitUntilExit()
            }
            sessions.removeValue(forKey: cfg.id)
        }
        _ = try await session(for: cfg)
    }

    // MARK: - Batch Tool Calls

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
                        return (index, call.serverId ?? "", "", error.localizedDescription, true, error.localizedDescription)
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

    public func shutdownAll() async {
        for (_, session) in sessions {
            await session.client.disconnect()
            if session.process.isRunning {
                session.process.terminate()
            }
        }
        sessions.removeAll()
    }

    private static func defaultResolveServers() -> [MCPConfigLoader.DetectedServer] {
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

    private func resolveServers() -> [MCPConfigLoader.DetectedServer] {
        serverResolver()
            .filter { !$0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
        case let arr as [any Sendable]:
            return .array(arr.map { toValue($0) })
        case let dict as [String: Any]:
            var mapped: [String: Value] = [:]
            for (k, v) in dict {
                mapped[k] = toValue(v)
            }
            return .object(mapped)
        case let dict as [String: any Sendable]:
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
