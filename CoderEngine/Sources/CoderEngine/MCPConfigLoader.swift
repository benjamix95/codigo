import Foundation

/// Carica configurazioni MCP da Codex, Cursor, Claude Desktop, XDG e JSON locale
public enum MCPConfigLoader {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Path config Codex
    public static var codexConfigPath: URL {
        home.appendingPathComponent(".codex").appendingPathComponent("config.toml")
    }

    /// Path config Cursor globale (~/.cursor/mcp.json)
    public static var cursorMCPConfigPath: URL {
        home.appendingPathComponent(".cursor").appendingPathComponent("mcp.json")
    }

    /// Path config Claude Desktop (macOS)
    public static var claudeDesktopConfigPath: URL {
        home.appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Claude")
            .appendingPathComponent("claude_desktop_config.json")
    }

    /// Path config XDG / sistema (~/.config/mcp.json)
    public static var xdgConfigPath: URL {
        home.appendingPathComponent(".config").appendingPathComponent("mcp.json")
    }

    /// Path config sistema /etc (solo lettura)
    public static var systemConfigPath: URL {
        URL(fileURLWithPath: "/etc/mcp.json")
    }

    /// Sorgenti JSON mcpServers da controllare (path, sourceLabel)
    private static var jsonConfigSources: [(URL, String)] {
        [
            (cursorMCPConfigPath, "Cursor"),
            (claudeDesktopConfigPath, "Claude Desktop"),
            (xdgConfigPath, "Sistema (~/.config)"),
            (systemConfigPath, "Sistema (/etc)")
        ]
    }

    /// Path JSON server manuali CoderIDE
    public static var localMCPConfigPath: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CoderIDE", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mcp-servers.json")
    }
    
    /// Server rilevato da Codex config (sorgente auto)
    public struct DetectedServer: Identifiable {
        public let id: String
        public var name: String
        public var command: String
        public var args: [String]
        public var env: [String: String]
        public var source: String
        
        public init(id: String, name: String, command: String, args: [String], env: [String: String], source: String) {
            self.id = id
            self.name = name
            self.command = command
            self.args = args
            self.env = env
            self.source = source
        }
    }
    
    /// Carica server da ~/.codex/config.toml (sezione mcp_servers)
    public static func loadFromCodexConfig() -> [DetectedServer] {
        let path = codexConfigPath
        guard FileManager.default.fileExists(atPath: path.path),
              let content = try? String(contentsOf: path, encoding: .utf8) else {
            return []
        }
        return parseCodexMCPConfig(content)
    }

    /// Carica server da file JSON con formato mcpServers (Cursor, Claude Desktop, ~/.config, /etc)
    private static func loadFromJsonMCPFile(path: URL, sourceId: String, sourceLabel: String) -> [DetectedServer] {
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcpServers = json["mcpServers"] as? [String: [String: Any]] else {
            return []
        }
        var servers: [DetectedServer] = []
        for (name, cfg) in mcpServers {
            guard let command = cfg["command"] as? String, !command.isEmpty else { continue }
            let args: [String]
            if let a = cfg["args"] as? [String] { args = a }
            else if let a = cfg["args"] as? [Any] { args = a.compactMap { $0 as? String } }
            else { args = [] }
            var env: [String: String] = [:]
            if let e = cfg["env"] as? [String: String] { env = e }
            else if let e = cfg["env"] as? [String: Any] { env = e.compactMapValues { $0 as? String } }
            servers.append(DetectedServer(
                id: "\(sourceId)-\(name)",
                name: cfg["name"] as? String ?? name,
                command: command,
                args: args,
                env: env,
                source: sourceLabel
            ))
        }
        return servers
    }

    /// Carica tutti i server da sorgenti JSON (Cursor, Claude Desktop, XDG, /etc)
    private static func loadFromAllJsonSources() -> [DetectedServer] {
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

    /// Carica tutti i server rilevati (Codex + Cursor + Claude + XDG + /etc), evitando duplicati per nome
    public static func loadDetectedServers() -> [DetectedServer] {
        var seen = Set<String>()
        var result: [DetectedServer] = []
        for s in loadFromCodexConfig() + loadFromAllJsonSources() {
            if !seen.contains(s.name) {
                seen.insert(s.name)
                result.append(s)
            }
        }
        return result
    }
    
    /// Parser minimale per [mcp_servers.xxx] in TOML
    private static func parseCodexMCPConfig(_ content: String) -> [DetectedServer] {
        var servers: [DetectedServer] = []
        let lines = content.components(separatedBy: .newlines)
        var i = 0
        
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[mcp_servers."), line.hasSuffix("]") {
                let inner = line.dropFirst("[mcp_servers.".count).dropLast()
                let name = String(inner)
                var command = ""
                var args: [String] = []
                var env: [String: String] = [:]
                i += 1
                
                while i < lines.count {
                    let ln = lines[i]
                    if ln.trimmingCharacters(in: .whitespaces).hasPrefix("[") { break }
                    let trimmed = ln.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed.hasPrefix("#") { i += 1; continue }
                    
                    if let eq = trimmed.firstIndex(of: "=") {
                        let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
                        let value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                        
                        if key == "command" {
                            command = parseStringLiteral(value)
                        } else if key == "args" {
                            args = parseStringArray(value)
                        } else if key == "env" {
                            env = parseInlineTable(value)
                        }
                    }
                    i += 1
                }
                
                if !command.isEmpty {
                    servers.append(DetectedServer(
                        id: "codex-\(name)",
                        name: name,
                        command: command,
                        args: args,
                        env: env,
                        source: "Codex"
                    ))
                }
            } else {
                i += 1
            }
        }
        return servers
    }
    
    private static func parseStringLiteral(_ s: String) -> String {
        var r = s.trimmingCharacters(in: .whitespaces)
        if r.hasPrefix("\""), r.hasSuffix("\"") {
            r = String(r.dropFirst().dropLast())
            return r.replacingOccurrences(of: "\\\"", with: "\"")
        }
        return r
    }
    
    private static func parseStringArray(_ s: String) -> [String] {
        var r = s.trimmingCharacters(in: .whitespaces)
        guard r.hasPrefix("["), r.hasSuffix("]") else { return [] }
        r = String(r.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        if r.isEmpty { return [] }
        var result: [String] = []
        var current = ""
        var inQuote = false
        for c in r {
            if c == "\"" {
                if inQuote {
                    result.append(parseStringLiteral("\"\(current)\""))
                    current = ""
                }
                inQuote.toggle()
            } else if inQuote {
                current.append(c)
            } else if c == "," {
                continue
            }
        }
        if !current.isEmpty { result.append(parseStringLiteral("\"\(current)\"")) }
        return result
    }
    
    private static func parseInlineTable(_ s: String) -> [String: String] {
        var r = s.trimmingCharacters(in: .whitespaces)
        guard r.hasPrefix("{"), r.hasSuffix("}") else { return [:] }
        r = String(r.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        if r.isEmpty { return [:] }
        var result: [String: String] = [:]
        let pairs = r.components(separatedBy: ",")
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let k = parseStringLiteral(String(parts[0]).trimmingCharacters(in: .whitespaces))
                let v = parseStringLiteral(String(parts[1]).trimmingCharacters(in: .whitespaces))
                result[k] = v
            }
        }
        return result
    }
    
    /// Carica server manuali da JSON locale
    public static func loadManualServers() -> [MCPServerConfig] {
        let path = localMCPConfigPath
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let decoded = try? JSONDecoder().decode([MCPServerConfig].self, from: data) else {
            return []
        }
        return decoded
    }
    
    /// Salva server manuali in JSON locale
    public static func saveManualServers(_ servers: [MCPServerConfig]) throws {
        let data = try JSONEncoder().encode(servers)
        try data.write(to: localMCPConfigPath)
    }
}
