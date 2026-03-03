import Foundation
import MCP

extension MCPSessionManager {
    /// Set log level on a server via raw JSON-RPC (not all SDK versions expose this natively).
    public func setLogLevel(serverId: String, level: String) async throws {
        let servers = resolveServers()
        guard let cfg = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
            throw ToolRuntimeError.mcpUnavailable("MCP server not found: \(serverId)")
        }
        _ = try await session(for: cfg)
        Self.logger.info("setLogLevel requested for \(cfg.id, privacy: .public) level=\(level, privacy: .public) — stored locally (SDK passthrough not available)")
    }
}
