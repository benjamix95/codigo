import Foundation

/// Configurazione di un MCP server (come in Cursor/Codex)
public struct MCPServerConfig: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var command: String
    public var args: [String]
    public var env: [String: String]
    public var enabled: Bool
    
    public init(
        id: UUID = UUID(),
        name: String = "Nuovo server",
        command: String = "",
        args: [String] = [],
        env: [String: String] = [:],
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.enabled = enabled
    }
}
