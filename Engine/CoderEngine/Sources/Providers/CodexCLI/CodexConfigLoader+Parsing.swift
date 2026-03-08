import Foundation

extension CodexConfigLoader {
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
            let rawValue = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
            let value: String
            if key == "developer_instructions", rawValue.hasPrefix("\"\"\"") {
                let (multi, nextIndex) = parseMultilineValue(
                    lines: rawLines,
                    startIndex: index,
                    firstRawValue: rawValue
                )
                value = multi
                index = nextIndex
            } else {
                value = parseStringLiteral(rawValue)
                index += 1
            }

            if currentSection == "sandbox_workspace_write" {
                switch key {
                case "network_access":
                    config.networkAccess = parseBool(value)
                case "additional_write_roots":
                    config.additionalWriteRoots = parseArray(rawValue)
                default:
                    break
                }
                continue
            }

            switch key {
            case "sandbox_mode":
                config.sandboxMode = value
            case "fast_mode":
                config.fastMode = parseBool(value)
            case "model":
                config.model = value
            case "model_provider":
                config.modelProvider = value
            case "model_reasoning_effort":
                config.modelReasoningEffort = value
            case "model_reasoning_summary":
                config.modelReasoningSummary = value
            case "model_verbosity":
                config.modelVerbosity = value
            case "personality":
                config.personality = value
            case "developer_instructions":
                config.developerInstructions = value
            case "check_for_update_on_startup":
                config.checkForUpdateOnStartup = parseBool(value)
            default:
                break
            }
        }

        return config
    }

    private static func parseBool(_ raw: String) -> Bool? {
        switch raw.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
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
        return value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func parseMultilineValue(
        lines: [String],
        startIndex: Int,
        firstRawValue: String
    ) -> (String, Int) {
        var collected: [String] = []
        let first = String(firstRawValue.dropFirst(3))
        if let closing = first.range(of: "\"\"\"") {
            let inline = String(first[..<closing.lowerBound])
                .replacingOccurrences(of: "\\\"\\\"\\\"", with: "\"\"\"")
            return (inline, startIndex + 1)
        }
        if !first.isEmpty {
            collected.append(first)
        }

        var index = startIndex + 1
        while index < lines.count {
            let current = lines[index]
            if let closing = current.range(of: "\"\"\"") {
                let prefix = String(current[..<closing.lowerBound])
                    .replacingOccurrences(of: "\\\"\\\"\\\"", with: "\"\"\"")
                collected.append(prefix)
                return (collected.joined(separator: "\n"), index + 1)
            }
            collected.append(current)
            index += 1
        }

        return (collected.joined(separator: "\n"), index)
    }
}
