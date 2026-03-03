import Foundation

extension MCPConfigLoader {
    /// Carica tutti i server da sorgenti JSON (Cursor, Claude Desktop, XDG, /etc).
    static func loadFromAllJsonSources() -> [DetectedServer] {
        var result: [DetectedServer] = []
        for (path, label) in jsonConfigSources {
            let sourceId: String
            switch label {
            case "Cursor":
                sourceId = "cursor"
            case "Claude Desktop":
                sourceId = "claude"
            case "Sistema (~/.config)":
                sourceId = "xdg"
            case "Sistema (/etc)":
                sourceId = "etc"
            default:
                sourceId = "json"
            }
            result += loadFromJsonMCPFile(path: path, sourceId: sourceId, sourceLabel: label)
        }
        return result
    }

    /// Carica server da file JSON con formato mcpServers.
    static func loadFromJsonMCPFile(
        path: URL,
        sourceId: String,
        sourceLabel: String
    ) -> [DetectedServer] {
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcpServers = json["mcpServers"] as? [String: [String: Any]] else {
            return []
        }

        var servers: [DetectedServer] = []
        for (name, cfg) in mcpServers {
            guard let command = cfg["command"] as? String, !command.isEmpty else { continue }
            let args = parseArgs(from: cfg["args"])
            let env: [String: String]
            if let explicit = cfg["env"] as? [String: String] {
                env = explicit
            } else if let explicit = cfg["env"] as? [String: Any] {
                env = explicit.compactMapValues { $0 as? String }
            } else {
                env = [:]
            }

            let effectiveName = cfg["name"] as? String ?? name
            let identity = MCPServerIdentity.make(
                source: sourceId,
                name: effectiveName,
                origin: "json",
                sourcePath: path.path
            )
            servers.append(DetectedServer(
                id: identity.stableIdentifier,
                identity: identity,
                legacyID: "\(sourceId)-\(name)",
                name: effectiveName,
                command: command,
                args: args,
                env: env,
                source: sourceLabel
            ))
        }
        return servers
    }
}
