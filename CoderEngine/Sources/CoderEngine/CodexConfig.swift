import Foundation

/// Full config letta da ~/.codex/config.toml
public struct CodexConfig: Sendable, Equatable {
    public var sandboxMode: String?
    public var model: String?
    public var modelProvider: String?
    public var modelReasoningEffort: String?
    public var modelReasoningSummary: String?
    public var modelVerbosity: String?
    public var personality: String?
    public var networkAccess: Bool?
    public var additionalWriteRoots: [String]
    public var developerInstructions: String?
    public var checkForUpdateOnStartup: Bool?

    public init(
        sandboxMode: String? = nil,
        model: String? = nil,
        modelProvider: String? = nil,
        modelReasoningEffort: String? = nil,
        modelReasoningSummary: String? = nil,
        modelVerbosity: String? = nil,
        personality: String? = nil,
        networkAccess: Bool? = nil,
        additionalWriteRoots: [String] = [],
        developerInstructions: String? = nil,
        checkForUpdateOnStartup: Bool? = nil
    ) {
        self.sandboxMode = sandboxMode
        self.model = model
        self.modelProvider = modelProvider
        self.modelReasoningEffort = modelReasoningEffort
        self.modelReasoningSummary = modelReasoningSummary
        self.modelVerbosity = modelVerbosity
        self.personality = personality
        self.networkAccess = networkAccess
        self.additionalWriteRoots = additionalWriteRoots
        self.developerInstructions = developerInstructions
        self.checkForUpdateOnStartup = checkForUpdateOnStartup
    }
}

/// Parser e writer per ~/.codex/config.toml
public enum CodexConfigLoader {
    public static var codexHome: String {
        ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(NSHomeDirectory())/.codex"
    }

    public static var configPath: String {
        "\(codexHome)/config.toml"
    }

    public static func load() -> CodexConfig {
        let path = configPath
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return CodexConfig()
        }
        return parse(content)
    }

    public static func save(_ config: CodexConfig) {
        var lines: [String] = []

        func emit(_ key: String, _ value: String?) {
            guard let v = value, !v.isEmpty else { return }
            let escaped = v
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            lines.append("\(key) = \"\(escaped)\"")
        }
        func emitBool(_ key: String, _ value: Bool?) {
            guard let v = value else { return }
            lines.append("\(key) = \(v)")
        }

        emit("model", config.model)
        emit("model_provider", config.modelProvider)
        emit("model_reasoning_effort", config.modelReasoningEffort)
        emit("model_reasoning_summary", config.modelReasoningSummary)
        emit("model_verbosity", config.modelVerbosity)
        let validPersonalities = ["friendly", "pragmatic"]
        if let p = config.personality, validPersonalities.contains(p) {
            emit("personality", p)
        }
        emit("sandbox_mode", config.sandboxMode)
        emitBool("check_for_update_on_startup", config.checkForUpdateOnStartup)

        if let di = config.developerInstructions, !di.isEmpty {
            let escapedTriple = di.replacingOccurrences(of: "\"\"\"", with: "\\\"\\\"\\\"")
            lines.append("developer_instructions = \"\"\"")
            lines.append(escapedTriple)
            lines.append("\"\"\"")
        }

        if config.networkAccess != nil || !config.additionalWriteRoots.isEmpty {
            lines.append("")
            lines.append("[sandbox_workspace_write]")
            emitBool("network_access", config.networkAccess)
            if !config.additionalWriteRoots.isEmpty {
                let arr = config.additionalWriteRoots.map { "\"\($0)\"" }.joined(separator: ", ")
                lines.append("additional_write_roots = [\(arr)]")
            }
        }

        let dir = (configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Parser

    static func parse(_ content: String) -> CodexConfig {
        var config = CodexConfig()
        var currentSection = ""
        let rawLines = content.components(separatedBy: .newlines)
        var index = 0

        while index < rawLines.count {
            let line = rawLines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                index += 1
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                index += 1
                continue
            }

            guard let eqIdx = trimmed.firstIndex(of: "=") else {
                index += 1
                continue
            }
            let key = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            let rawVal = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
            let value: String
            if key == "developer_instructions", rawVal.hasPrefix("\"\"\"") {
                let (multi, nextIndex) = parseMultilineValue(lines: rawLines, startIndex: index, firstRawValue: rawVal)
                value = multi
                index = nextIndex
            } else {
                value = parseStringLiteral(rawVal)
                index += 1
            }

            if currentSection == "sandbox_workspace_write" {
                switch key {
                case "network_access": config.networkAccess = parseBool(value)
                case "additional_write_roots": config.additionalWriteRoots = parseArray(rawVal)
                default: break
                }
                continue
            }

            switch key {
            case "sandbox_mode": config.sandboxMode = value
            case "model": config.model = value
            case "model_provider": config.modelProvider = value
            case "model_reasoning_effort": config.modelReasoningEffort = value
            case "model_reasoning_summary": config.modelReasoningSummary = value
            case "model_verbosity": config.modelVerbosity = value
            case "personality": config.personality = value
            case "developer_instructions": config.developerInstructions = value
            case "check_for_update_on_startup": config.checkForUpdateOnStartup = parseBool(value)
            default: break
            }
        }

        return config
    }

    private static func parseBool(_ s: String) -> Bool? {
        switch s.lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    private static func parseArray(_ raw: String) -> [String] {
        let inner = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "^\\[|\\]$", with: "", options: .regularExpression)
        return inner.components(separatedBy: ",")
            .map { parseStringLiteral($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func parseStringLiteral(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        value = value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
        return value
    }

    private static func parseMultilineValue(lines: [String], startIndex: Int, firstRawValue: String) -> (String, Int) {
        var collected: [String] = []
        let first = String(firstRawValue.dropFirst(3))
        if let closing = first.range(of: "\"\"\"") {
            let inline = String(first[..<closing.lowerBound])
                .replacingOccurrences(of: "\\\"\\\"\\\"", with: "\"\"\"")
            return (inline, startIndex + 1)
        }
        if !first.isEmpty { collected.append(first) }

        var i = startIndex + 1
        while i < lines.count {
            let current = lines[i]
            if let closing = current.range(of: "\"\"\"") {
                let prefix = String(current[..<closing.lowerBound])
                    .replacingOccurrences(of: "\\\"\\\"\\\"", with: "\"\"\"")
                collected.append(prefix)
                return (collected.joined(separator: "\n"), i + 1)
            }
            collected.append(current)
            i += 1
        }
        return (collected.joined(separator: "\n"), i)
    }
}
