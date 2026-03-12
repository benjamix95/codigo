import Foundation

extension MCPSessionManager {
    func rustCallToolsBatch(
        calls: [(serverId: String?, toolName: String, arguments: [String: Any])],
        idleTTLSeconds: Int = 300
    ) async throws -> [(index: Int, serverId: String, serverName: String, content: String, isError: Bool, error: String?)] {
        await evictIdleSessions(idleTTLSeconds: idleTTLSeconds)
        let servers = resolveServers()
        guard !servers.isEmpty else { return [] }

        var requestItems: [MCPLifecycleRustBatchCallRequestItem] = []
        requestItems.reserveCapacity(calls.count)

        for (index, call) in calls.enumerated() {
            let target = try await resolveTargetServer(
                serverId: call.serverId,
                toolName: call.toolName,
                servers: servers
            )
            requestItems.append(
                MCPLifecycleRustBatchCallRequestItem(
                    index: index,
                    server: MCPLifecycleRustServerConfig(server: target),
                    toolName: call.toolName,
                    arguments: jsonObjectArguments(fromRich: call.arguments)
                )
            )
        }

        let payload = try await rustLifecycleBackend.callToolsBatch(calls: requestItems)
        return payload.results
            .sorted { $0.index < $1.index }
            .map {
                (
                    index: $0.index,
                    serverId: $0.serverId,
                    serverName: $0.serverName,
                    content: $0.content,
                    isError: $0.isError,
                    error: $0.error
                )
            }
    }
}
