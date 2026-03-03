import Foundation

extension MCPSessionManager {
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
}
