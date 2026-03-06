import CoderEngine

enum MCPServerControlService {
    static var sessionManager: MCPSessionManager {
        MCPRuntimeService.sharedSessionManager
    }

    static func restart(serverId: String) async throws {
        try await sessionManager.restartServer(serverId: serverId)
        _ = try await sessionManager.listTools(serverId: serverId, idleTTLSeconds: 0)
    }
}
