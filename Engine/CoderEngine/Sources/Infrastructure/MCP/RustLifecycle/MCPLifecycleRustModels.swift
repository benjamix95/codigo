import Foundation

struct MCPLifecycleRustServerConfig: Sendable {
    let id: String
    let name: String
    let command: String
    let args: [String]
    let cwd: String?
    let env: [String: String]

    init(server: MCPConfigLoader.DetectedServer, cwd: String? = nil) {
        self.id = server.id
        self.name = server.name
        self.command = server.command
        self.args = server.args
        self.cwd = cwd
        self.env = server.env
    }

    var jsonObject: [String: Any] {
        var payload: [String: Any] = [
            "id": id,
            "name": name,
            "command": command,
            "args": args,
            "env": env
        ]
        if let cwd, !cwd.isEmpty {
            payload["cwd"] = cwd
        }
        return payload
    }
}

struct MCPLifecycleRustListedServer: Decodable, Sendable {
    let id: String
    let name: String
    let status: String
}

struct MCPLifecycleRustToolDescriptor: Decodable, Sendable {
    let name: String
    let description: String
    let schema: String
    let serverId: String
    let serverName: String

    func asSessionToolDescriptor() -> MCPToolDescriptor {
        MCPToolDescriptor(
            name: name,
            description: description,
            schema: schema,
            serverId: serverId,
            serverName: serverName
        )
    }
}

struct MCPLifecycleRustListServersPayload: Decodable, Sendable {
    let servers: [MCPLifecycleRustListedServer]
}

struct MCPLifecycleRustHealthPayload: Decodable, Sendable {
    let states: [String: String]
}

struct MCPLifecycleRustListToolsPayload: Decodable, Sendable {
    let tools: [MCPLifecycleRustToolDescriptor]
}

struct MCPLifecycleRustCallToolPayload: Decodable, Sendable {
    let serverId: String
    let serverName: String
    let content: String
    let isError: Bool
}

struct MCPLifecycleRustServerActionPayload: Decodable, Sendable {
    let serverId: String
    let serverName: String
    let status: String
}

struct MCPLifecycleRustShutdownPayload: Decodable, Sendable {
    let stopped: Int
}
