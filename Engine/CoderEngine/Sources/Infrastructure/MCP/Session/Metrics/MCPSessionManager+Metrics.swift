import Foundation

extension MCPSessionManager {
    public func serverMetrics(serverId: String? = nil) async -> [MCPServerMetrics] {
        let servers = resolveServers()
        var targets = servers
        if let serverId, !serverId.isEmpty {
            targets = servers.filter { $0.id == serverId || $0.name == serverId }
        }
        let states = (try? await rustHealthStates(for: targets)) ?? [:]

        var results: [MCPServerMetrics] = []
        for cfg in targets {
            let stats = await callMetrics.metrics(for: cfg.id)
            let status: String
            let toolCount: Int
            let resourceCount: Int
            let promptCount: Int
            var capabilities = MCPServerCapabilities(supportsTools: false, supportsResources: false, supportsPrompts: false, supportsLogging: false, supportsResourceSubscriptions: false)

            let rustStatus = states[cfg.id]?.lowercased()
            if rustStatus == "ready" || rustStatus == "disconnected" || rustStatus == "stopped" || rustStatus == "failed" {
                status = rustStatus ?? "disconnected"
                toolCount = (try? await rustToolDescriptors(for: cfg).count) ?? 0
                if sessions[cfg.id] != nil {
                    resourceCount = (try? await resourcesForServer(cfg).count) ?? 0
                    promptCount = (try? await promptsForServer(cfg).count) ?? 0
                } else {
                    resourceCount = 0
                    promptCount = 0
                }
                capabilities = MCPServerCapabilities(
                    supportsTools: toolCount > 0,
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
