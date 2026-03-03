import Foundation

extension MCPConfigLoader {
    static func parseTomlString(from raw: String) -> String? {
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

    static func parseTomlPrimitiveAsString(_ raw: String) -> String {
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

    static func parseStringLiteral(_ s: String) -> String {
        return parseTomlPrimitiveAsString(s)
    }

    static func parseCommaSeparatedComponents(_ input: String, separator: Character) -> [String] {
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

    static func parseStringArray(_ s: String) -> [String] {
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

    static func parseStringArrayStrict(_ raw: String, line: Int, key: String) throws -> [String] {
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

    static func parseInlineTable(_ s: String) -> [String: String] {
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

    static func parseInlineTableStrict(_ raw: String, line: Int, key: String) throws -> [String: String] {
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

    static func stripInlineComment(from raw: String) -> String {
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

    static func isCompatibilityParsingEnabled() -> Bool {
        let envValue = ProcessInfo.processInfo.environment["CODERIDE_MCP_TOML_COMPAT_MODE"] ?? ""
        let normalized = envValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "1" || normalized == "true" || normalized == "yes"
    }

    static func emitIdentityConflictWarning(existing: DetectedServer, incoming: DetectedServer) {
        let existingPath = existing.identity.sourcePath ?? "<unknown>"
        let incomingPath = incoming.identity.sourcePath ?? "<unknown>"
        print(
            "[MCPConfigLoader] ⚠️ MCP identity conflict '\(incoming.name)' " +
            "[\(incoming.identity.logicalIdentifier)] between '\(existingPath)' and '\(incomingPath)'. " +
            "Keeping both identities (stable IDs differ)."
        )
    }

    static func parseArgs(from raw: Any?) -> [String] {
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
}
