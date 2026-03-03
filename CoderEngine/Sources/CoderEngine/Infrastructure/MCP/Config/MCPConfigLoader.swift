import Foundation

/// Carica configurazioni MCP da Codex, Cursor, Claude Desktop, XDG e JSON locale.
public enum MCPConfigLoader {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Path config Codex.
    public static var codexConfigPath: URL {
        home.appendingPathComponent(".codex").appendingPathComponent("config.toml")
    }

    /// Path config Cursor globale (~/.cursor/mcp.json).
    public static var cursorMCPConfigPath: URL {
        home.appendingPathComponent(".cursor").appendingPathComponent("mcp.json")
    }

    /// Path config Claude Desktop (macOS).
    public static var claudeDesktopConfigPath: URL {
        home.appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Claude")
            .appendingPathComponent("claude_desktop_config.json")
    }

    /// Path config XDG / sistema (~/.config/mcp.json).
    public static var xdgConfigPath: URL {
        home.appendingPathComponent(".config").appendingPathComponent("mcp.json")
    }

    /// Path config sistema /etc (solo lettura).
    public static var systemConfigPath: URL {
        URL(fileURLWithPath: "/etc/mcp.json")
    }

    /// Sorgenti JSON mcpServers da controllare (path, sourceLabel).
    static var jsonConfigSources: [(URL, String)] {
        [
            (cursorMCPConfigPath, "Cursor"),
            (claudeDesktopConfigPath, "Claude Desktop"),
            (xdgConfigPath, "Sistema (~/.config)"),
            (systemConfigPath, "Sistema (/etc)")
        ]
    }

    /// Path JSON server manuali CoderIDE.
    public static var localMCPConfigPath: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CoderIDE", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mcp-servers.json")
    }

    /// Server rilevato da Codex config (sorgente auto).
    public struct DetectedServer: Identifiable {
        public let id: String
        public let identity: MCPServerIdentity
        public let legacyID: String?
        public var name: String
        public var command: String
        public var args: [String]
        public var env: [String: String]
        public var source: String

        public init(
            id: String,
            identity: MCPServerIdentity,
            legacyID: String? = nil,
            name: String,
            command: String,
            args: [String],
            env: [String: String],
            source: String
        ) {
            self.id = id
            self.identity = identity
            self.legacyID = legacyID
            self.name = name
            self.command = command
            self.args = args
            self.env = env
            self.source = source
        }
    }

    /// Carica server da ~/.codex/config.toml (sezione mcp_servers).
    public static func loadFromCodexConfig() -> [DetectedServer] {
        let path = codexConfigPath
        guard FileManager.default.fileExists(atPath: path.path),
              let content = try? String(contentsOf: path, encoding: .utf8) else {
            return []
        }
        let compatModeEnabled = isCompatibilityParsingEnabled()
        do {
            return try parseCodexMCPConfigStrict(content, sourcePath: path.path)
        } catch let parseError as TOMLParseError {
            print("[MCPConfigLoader] ⚠️ Codex MCP config parse error: \(parseError.localizedDescription)")
            guard compatModeEnabled else { return [] }
            print("[MCPConfigLoader] ℹ️ Compat mode enabled, using best-effort parser fallback.")
            return parseCodexMCPConfigLegacy(content, sourcePath: path.path)
        } catch {
            print("[MCPConfigLoader] ⚠️ Codex MCP config parse error: \(error.localizedDescription)")
            guard compatModeEnabled else { return [] }
            print("[MCPConfigLoader] ℹ️ Compat mode enabled, using best-effort parser fallback.")
            return parseCodexMCPConfigLegacy(content, sourcePath: path.path)
        }
    }

    /// Carica tutti i server rilevati (Codex + Cursor + Claude + XDG + /etc),
    /// deduplicando per identità stabile composta.
    public static func loadDetectedServers() -> [DetectedServer] {
        deduplicateDetectedServers(loadFromCodexConfig() + loadFromAllJsonSources())
    }

    static func parseCodexMCPConfigForTests(
        _ content: String,
        sourcePath: String = "/tmp/test-config.toml",
        compatibilityMode: Bool = false
    ) throws -> [DetectedServer] {
        do {
            return try parseCodexMCPConfigStrict(content, sourcePath: sourcePath)
        } catch {
            if compatibilityMode {
                return parseCodexMCPConfigLegacy(content, sourcePath: sourcePath)
            }
            throw error
        }
    }

    /// Carica server manuali da JSON locale.
    public static func loadManualServers() -> [MCPServerConfig] {
        let path = localMCPConfigPath
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let decoded = try? JSONDecoder().decode([MCPServerConfig].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Salva server manuali in JSON locale.
    public static func saveManualServers(_ servers: [MCPServerConfig]) throws {
        let data = try JSONEncoder().encode(servers)
        try data.write(to: localMCPConfigPath)
    }

    static func deduplicateDetectedServers(_ input: [DetectedServer]) -> [DetectedServer] {
        var seenStable = Set<String>()
        var seenLogical: [String: DetectedServer] = [:]
        var result: [DetectedServer] = []
        for server in input {
            let stableID = server.identity.stableIdentifier
            if !seenStable.insert(stableID).inserted {
                continue
            }

            let logicalID = server.identity.logicalIdentifier
            if let existing = seenLogical[logicalID],
               existing.identity.stableIdentifier != stableID {
                emitIdentityConflictWarning(existing: existing, incoming: server)
            }
            seenLogical[logicalID] = server
            result.append(server)
        }
        return result
    }

    static func loadDisabledServerIDs() -> Set<String> {
        guard let data = UserDefaults.standard.string(forKey: "mcp_disabled_ids")?.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(ids)
    }
}
