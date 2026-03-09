import Foundation
import MCP
import os

public actor MCPSessionManager {
    public static let shared = MCPSessionManager()

    static let logger = Logger(subsystem: "com.codigo.CoderEngine", category: "MCPSessionManager")
    var sessions: [String: MCPServerSession] = [:]
    let retryPolicy: MCPRetryPolicy
    let serverResolver: () -> [MCPConfigLoader.DetectedServer]
    /// TTL for cached tool lists before re-fetching (seconds).
    let toolCacheTTL: TimeInterval = 300

    public let logStore = MCPLogStore()
    public let callMetrics = MCPCallMetricsTracker()
    var resourceSubscriptions: [String: Set<String>] = [:]

    public init(
        retryPolicy: MCPRetryPolicy = .default,
        serverResolver: (() -> [MCPConfigLoader.DetectedServer])? = nil
    ) {
        self.retryPolicy = retryPolicy
        self.serverResolver = serverResolver ?? {
            MCPSessionManager.defaultResolveServers()
        }
    }
}
