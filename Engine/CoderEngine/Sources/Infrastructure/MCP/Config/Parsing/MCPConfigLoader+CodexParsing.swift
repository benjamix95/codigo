import Foundation

extension MCPConfigLoader {
    struct TOMLParseError: LocalizedError {
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

    struct ParsedMCPSection {
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

    static func parseCodexMCPConfigStrict(_ content: String, sourcePath: String) throws -> [DetectedServer] {
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
            case "enabled", "required", "tool_timeout_sec":
                break
            default:
                print("[MCPConfigLoader] ℹ️ Ignoring unsupported key '\(key)' in [mcp_servers.\(section.name)] at line \(lineNumber)")
            }
            currentSection = section
        }

        try flushCurrentSection()
        return servers
    }

    /// Parser legacy best-effort (compat mode).
    static func parseCodexMCPConfigLegacy(_ content: String, sourcePath: String) -> [DetectedServer] {
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
                    if trimmed.isEmpty || trimmed.hasPrefix("#") {
                        i += 1
                        continue
                    }

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
}
