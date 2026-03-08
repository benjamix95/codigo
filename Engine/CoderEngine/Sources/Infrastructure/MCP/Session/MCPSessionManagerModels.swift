import Foundation
import MCP

public struct MCPNullValue: Sendable, Hashable {
    public init() {}
}

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
        let normalizedInput = severity
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalized = normalizedInput == "warn" ? "warning" : normalizedInput
        guard let idx = ordered.firstIndex(of: normalized) else {
            return Set(ordered)
        }
        return Set(ordered[idx...])
    }
}

public struct MCPLogEntry: Sendable {
    public let timestamp: Date
    public let level: String
    public let message: String
    public let serverId: String
    public let serverName: String
    public let logger: String?
}

/// MCP metrics snapshot per server.
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
