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
    
    /// Carica server da ~/.codex/config.toml (sezione mcp_servers)
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
            let args = parseArgs(from: cfg["args"])
            var env: [String: String] = [:]
            if let e = cfg["env"] as? [String: String] { env = e }
            else if let e = cfg["env"] as? [String: Any] { env = e.compactMapValues { $0 as? String } }
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

    /// Carica tutti i server rilevati (Codex + Cursor + Claude + XDG + /etc),
    /// deduplicando per identità stabile composta.
    public static func loadDetectedServers() -> [DetectedServer] {
        deduplicateDetectedServers(loadFromCodexConfig() + loadFromAllJsonSources())
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
    
    private struct TOMLParseError: LocalizedError {
        let line: Int
        let key: String?
        let message: String

        var errorDescription: String? {
            if let key, !key.isEmpty {
                return "line \(line), key '\(key)': \(message)"
            }
            return "line \(line): \(message)"
        }
    }

    private struct ParsedMCPSection {
        let name: String
        let sectionLine: Int
        var command: String?
        var args: [String]
        var env: [String: String]

        init(name: String, sectionLine: Int) {
            self.name = name
            self.sectionLine = sectionLine
            self.command = nil
            self.args = []
            self.env = [:]
        }
    }

    /// Parser TOML fail-fast con diagnostica (linea/chiave).
    private static func parseCodexMCPConfigStrict(_ content: String, sourcePath: String) throws -> [DetectedServer] {
        let lines = content.components(separatedBy: .newlines)
        var servers: [DetectedServer] = []
        var currentSection: ParsedMCPSection?

        func flushCurrentSection() throws {
            guard let section = currentSection else { return }
            guard let command = section.command?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty else {
                throw TOMLParseError(
                    line: section.sectionLine,
                    key: "command",
                    message: "missing required command in [mcp_servers.\(section.name)]"
                )
            }
            let identity = MCPServerIdentity.make(
                source: "codex",
                name: section.name,
                origin: "toml",
                sourcePath: sourcePath
            )
            servers.append(DetectedServer(
                id: identity.stableIdentifier,
                identity: identity,
                legacyID: "codex-\(section.name)",
                name: section.name,
                command: command,
                args: section.args,
                env: section.env,
                source: "Codex"
            ))
            currentSection = nil
        }

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                try flushCurrentSection()
                let sectionName = String(trimmed.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if sectionName.hasPrefix("mcp_servers.") {
                    let serverName = String(sectionName.dropFirst("mcp_servers.".count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if serverName.isEmpty {
                        throw TOMLParseError(
                            line: lineNumber,
                            key: nil,
                            message: "invalid MCP server section header"
                        )
                    }
                    currentSection = ParsedMCPSection(name: serverName, sectionLine: lineNumber)
                } else {
                    currentSection = nil
                }
                continue
            }

            guard var section = currentSection else {
                continue
            }

            let lineWithoutComment = stripInlineComment(from: rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if lineWithoutComment.isEmpty { continue }

            guard let eqIndex = lineWithoutComment.firstIndex(of: "=") else {
                throw TOMLParseError(
                    line: lineNumber,
                    key: nil,
                    message: "expected key = value assignment"
                )
            }

            let key = String(lineWithoutComment[..<eqIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = String(lineWithoutComment[lineWithoutComment.index(after: eqIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                throw TOMLParseError(line: lineNumber, key: nil, message: "empty key before '='")
            }
            if rawValue.isEmpty {
                throw TOMLParseError(line: lineNumber, key: key, message: "missing value")
            }

            switch key {
            case "command":
                guard let parsed = parseTomlString(from: rawValue), !parsed.isEmpty else {
                    throw TOMLParseError(
                        line: lineNumber,
                        key: key,
                        message: "command must be a quoted TOML string"
                    )
                }
                section.command = parsed
            case "args":
                section.args = try parseStringArrayStrict(rawValue, line: lineNumber, key: key)
            case "env":
                section.env = try parseInlineTableStrict(rawValue, line: lineNumber, key: key)
            default:
                print("[MCPConfigLoader] ℹ️ Ignoring unsupported key '\(key)' in [mcp_servers.\(section.name)] at line \(lineNumber)")
            }
            currentSection = section
        }

        try flushCurrentSection()
        return servers
    }

    /// Parser legacy best-effort (compat mode).
    private static func parseCodexMCPConfigLegacy(_ content: String, sourcePath: String) -> [DetectedServer] {
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
                    let identity = MCPServerIdentity.make(
                        source: "codex",
                        name: name,
                        origin: "toml",
                        sourcePath: sourcePath
                    )
                    servers.append(DetectedServer(
                        id: identity.stableIdentifier,
                        identity: identity,
                        legacyID: "codex-\(name)",
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
        return parseTomlPrimitiveAsString(s)
    }
    
    private static func parseTomlString(from raw: String) -> String? {
        var r = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard r.count >= 2,
              r.hasPrefix("\""),
              r.hasSuffix("\"") else { return nil }
        r = String(r.dropFirst().dropLast())

        var out: String = ""
        var escaped = false
        for ch in r {
            if escaped {
                switch ch {
                case "\\":
                    out.append("\\")
                case "\"":
                    out.append("\"")
                case "n":
                    out.append("\n")
                case "r":
                    out.append("\r")
                case "t":
                    out.append("\t")
                default:
                    out.append(ch)
                }
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
            } else {
                out.append(ch)
            }
        }
        if escaped { out.append("\\") }
        return out
    }

    private static func parseTomlPrimitiveAsString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if let quoted = parseTomlString(from: trimmed) { return quoted }

        var value = trimmed
        if value.hasPrefix("'") && value.hasSuffix("'") {
            value = String(value.dropFirst().dropLast())
        }
        if value == "true" || value == "false" || value == "null" {
            return value
        }
        if Double(value) != nil || Int(value) != nil {
            return value
        }
        return trimmed
    }

    private static func parseCommaSeparatedComponents(_ input: String, separator: Character) -> [String] {
        var components: [String] = []
        var current: [Character] = []
        var inQuote = false
        var escaped = false

        for ch in input {
            if escaped {
                current.append("\\")
                current.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" && inQuote {
                escaped = true
                continue
            }
            if ch == "\"" {
                inQuote.toggle()
            } else if ch == separator && !inQuote {
                components.append(String(current).trimmingCharacters(in: .whitespacesAndNewlines))
                current.removeAll(keepingCapacity: true)
            } else if ch == "#" && !inQuote {
                break
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            components.append(String(current).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return components.filter { !$0.isEmpty }
    }

    private static func parseStringArrayStrict(_ raw: String, line: Int, key: String) throws -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
            throw TOMLParseError(line: line, key: key, message: "args must be a TOML array")
        }
        let items = parseStringArray(trimmed)
        let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        if !inner.isEmpty && items.isEmpty {
            throw TOMLParseError(line: line, key: key, message: "failed to parse args array")
        }
        return items
    }

    private static func parseStringArray(_ s: String) -> [String] {
        var r = s.trimmingCharacters(in: .whitespaces)
        guard r.hasPrefix("["), r.hasSuffix("]") else { return [] }
        r = String(r.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        if r.isEmpty { return [] }
        return parseCommaSeparatedComponents(r, separator: ",").map { component in
            if let quoted = parseTomlString(from: component) {
                return quoted
            }
            return parseTomlPrimitiveAsString(component)
        }
    }
    
    private static func parseInlineTable(_ s: String) -> [String: String] {
        var r = s.trimmingCharacters(in: .whitespaces)
        guard r.hasPrefix("{"), r.hasSuffix("}") else { return [:] }
        r = String(r.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        if r.isEmpty { return [:] }
        var result: [String: String] = [:]
        let pairs = parseCommaSeparatedComponents(r, separator: ",")
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

    private static func parseInlineTableStrict(_ raw: String, line: Int, key: String) throws -> [String: String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else {
            throw TOMLParseError(line: line, key: key, message: "env must be an inline TOML table")
        }
        let parsed = parseInlineTable(trimmed)
        let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        if !inner.isEmpty && parsed.isEmpty {
            throw TOMLParseError(line: line, key: key, message: "failed to parse env inline table")
        }
        return parsed
    }

    private static func stripInlineComment(from raw: String) -> String {
        var output = ""
        var inQuote = false
        var escaped = false
        for ch in raw {
            if escaped {
                output.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" && inQuote {
                output.append(ch)
                escaped = true
                continue
            }
            if ch == "\"" {
                inQuote.toggle()
                output.append(ch)
                continue
            }
            if ch == "#" && !inQuote {
                break
            }
            output.append(ch)
        }
        return output
    }

    private static func isCompatibilityParsingEnabled() -> Bool {
        let envValue = ProcessInfo.processInfo.environment["CODERIDE_MCP_TOML_COMPAT_MODE"] ?? ""
        let normalized = envValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "1" || normalized == "true" || normalized == "yes"
    }

    private static func emitIdentityConflictWarning(existing: DetectedServer, incoming: DetectedServer) {
        let existingPath = existing.identity.sourcePath ?? "<unknown>"
        let incomingPath = incoming.identity.sourcePath ?? "<unknown>"
        print(
            "[MCPConfigLoader] ⚠️ MCP identity conflict '\(incoming.name)' " +
            "[\(incoming.identity.logicalIdentifier)] between '\(existingPath)' and '\(incomingPath)'. " +
            "Keeping both identities (stable IDs differ)."
        )
    }

    private static func parseArgs(from raw: Any?) -> [String] {
        guard let raw else { return [] }
        if let array = raw as? [Any] {
            return array.map { element in
                switch element {
                case let value as String:
                    return value
                case let value as NSNumber:
                    return value.stringValue
                case let value as Bool:
                    return value.description
                case let value as [String]:
                    return value.joined(separator: " ")
                case let value as [Any]:
                    return value.map { String(describing: $0) }.joined(separator: ",")
                case let value as [String: Any]:
                    return String(describing: value)
                case _ as NSNull:
                    return "null"
                default:
                    return "\(element)"
                }
            }
        }
        if let args = raw as? [String] { return args }
        if let arg = raw as? String { return parseCommaSeparatedComponents(arg, separator: ",") }
        return []
    }

    static func loadDisabledServerIDs() -> Set<String> {
        guard let data = UserDefaults.standard.string(forKey: "mcp_disabled_ids")?.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(ids)
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
