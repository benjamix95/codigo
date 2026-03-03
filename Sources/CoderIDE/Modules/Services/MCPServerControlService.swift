import CoderEngine

enum MCPServerControlService {
    static func restart(serverId: String) async throws {
        let manager = MCPSessionManager()
        do {
            try await manager.restartServer(serverId: serverId)
        } catch {
            await manager.shutdownAll()
            throw error
        }
        await manager.shutdownAll()
    }
}
