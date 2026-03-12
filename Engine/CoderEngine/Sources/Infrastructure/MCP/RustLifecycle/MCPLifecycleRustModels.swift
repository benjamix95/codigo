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

struct MCPLifecycleRustURIAckPayload: Decodable, Sendable {
    let uri: String
}

struct MCPLifecycleRustResourceDescriptor: Decodable, Sendable {
    let uri: String
    let name: String
    let title: String?
    let description: String?
    let mimeType: String?
    let serverId: String
    let serverName: String

    func asSessionResourceDescriptor() -> MCPResourceDescriptor {
        MCPResourceDescriptor(
            uri: uri,
            name: title ?? name,
            description: description,
            mimeType: mimeType,
            serverId: serverId,
            serverName: serverName
        )
    }
}

struct MCPLifecycleRustResourceContent: Decodable, Sendable {
    let uri: String
    let mimeType: String?
    let text: String?
    let blob: String?

    func asSessionResourceContent(
        serverId: String,
        serverName: String
    ) -> MCPResourceContent {
        MCPResourceContent(
            uri: uri,
            mimeType: mimeType,
            text: text,
            blob: blob,
            serverId: serverId,
            serverName: serverName
        )
    }
}

struct MCPLifecycleRustResourceTemplate: Decodable, Sendable {
    let uriTemplate: String
    let name: String
    let title: String?
    let description: String?
    let mimeType: String?
    let serverId: String
    let serverName: String

    func asSessionResourceTemplate() -> MCPResourceTemplate {
        MCPResourceTemplate(
            uriTemplate: uriTemplate,
            name: title ?? name,
            description: description,
            mimeType: mimeType,
            serverId: serverId,
            serverName: serverName
        )
    }
}

struct MCPLifecycleRustPromptArgument: Decodable, Sendable {
    let name: String
    let title: String?
    let description: String?
    let required: Bool?
}

struct MCPLifecycleRustPromptDescriptor: Decodable, Sendable {
    let name: String
    let title: String?
    let description: String?
    let arguments: [MCPLifecycleRustPromptArgument]
    let serverId: String
    let serverName: String

    func asSessionPromptDescriptor() -> MCPPromptDescriptor {
        MCPPromptDescriptor(
            name: name,
            description: description ?? title,
            arguments: arguments.map {
                MCPPromptArgument(
                    name: $0.name,
                    description: $0.description ?? $0.title,
                    required: $0.required ?? false
                )
            },
            serverId: serverId,
            serverName: serverName
        )
    }
}

struct MCPLifecycleRustPromptMessageContent: Decodable, Sendable {
    let type: String
    let text: String?
    let data: String?
    let mimeType: String?
    let resource: MCPLifecycleRustResourceContent?

    func displayString() -> String {
        switch type {
        case "text":
            return text ?? ""
        case "image":
            return "[image \(mimeType ?? "unknown")] \(data?.prefix(100) ?? "")..."
        case "audio":
            return "[audio \(mimeType ?? "unknown")] \(data?.prefix(100) ?? "")..."
        case "resource":
            return "[resource: \(resource?.uri ?? "unknown")]"
        default:
            return "[content: \(type)]"
        }
    }
}

struct MCPLifecycleRustPromptMessage: Decodable, Sendable {
    let role: String
    let content: MCPLifecycleRustPromptMessageContent

    func asSessionPromptMessage() -> MCPPromptMessage {
        MCPPromptMessage(role: role, content: content.displayString())
    }
}

struct MCPLifecycleRustListResourcesPayload: Decodable, Sendable {
    let resources: [MCPLifecycleRustResourceDescriptor]
}

struct MCPLifecycleRustReadResourcePayload: Decodable, Sendable {
    let contents: [MCPLifecycleRustResourceContent]
}

struct MCPLifecycleRustListResourceTemplatesPayload: Decodable, Sendable {
    let templates: [MCPLifecycleRustResourceTemplate]
}

struct MCPLifecycleRustListPromptsPayload: Decodable, Sendable {
    let prompts: [MCPLifecycleRustPromptDescriptor]
}

struct MCPLifecycleRustGetPromptPayload: Decodable, Sendable {
    let description: String?
    let messages: [MCPLifecycleRustPromptMessage]
}
