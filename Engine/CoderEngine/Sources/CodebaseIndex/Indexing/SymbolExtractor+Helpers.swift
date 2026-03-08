import Foundation

extension SymbolExtractor {
    // MARK: - Regex Helpers

    /// Returns first match of a pattern in a string
    static func firstMatch(pattern: String, in string: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range) else { return nil }
        return String(string[Range(match.range, in: string)!])
    }

    /// Returns all capture groups of first match
    static func matchGroups(pattern: String, in string: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        else { return [] }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range) else { return [] }
        var groups: [String] = []
        for i in 1..<match.numberOfRanges {
            if let r = Range(match.range(at: i), in: string) {
                groups.append(String(string[r]))
            } else {
                groups.append("")
            }
        }
        return groups
    }

    /// Returns all capture groups including group 0 (nil-safe)
    static func matchGroupsFull(pattern: String, in string: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range) else { return nil }
        var groups: [String] = []
        for i in 1..<match.numberOfRanges {
            if let r = Range(match.range(at: i), in: string) {
                groups.append(String(string[r]))
            } else {
                groups.append("")
            }
        }
        return groups.isEmpty ? nil : groups
    }

    /// Returns all matches of group N across the string
    static func matchAll(pattern: String, in string: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        else { return [] }
        let range = NSRange(string.startIndex..., in: string)
        let matches = regex.matches(in: string, range: range)
        var results: [String] = []
        for match in matches {
            guard group < match.numberOfRanges else { continue }
            if let r = Range(match.range(at: group), in: string) {
                results.append(String(string[r]))
            }
        }
        return results
    }

    // MARK: - Block Finding

    /// Find the end of a brace-delimited block starting at a given line (C-style languages)
    static func findBlockEnd(lines: [String], startLine: Int) -> Int {
        var depth = 0
        var foundOpen = false
        for i in startLine..<lines.count {
            for ch in lines[i] {
                if ch == "{" {
                    depth += 1
                    foundOpen = true
                } else if ch == "}" {
                    depth -= 1
                    if foundOpen && depth == 0 {
                        return i
                    }
                }
            }
            // If we went past 2000 lines without closing, bail
            if i - startLine > 2000 { return startLine }
        }
        return startLine
    }

    /// Find the end of a Python-style indentation block
    static func findPythonBlockEnd(lines: [String], startLine: Int, startIndent: Int) -> Int {
        for i in (startLine + 1)..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            if indent <= startIndent {
                return max(startLine, i - 1)
            }
        }
        return max(startLine, lines.count - 1)
    }

    // MARK: - Doc Comments

    /// Extract doc comment (/// or /** */) immediately before a line
    static func extractDocComment(lines: [String], beforeLine: Int) -> String? {
        var docLines: [String] = []
        var i = beforeLine - 1
        while i >= 0 {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("///") {
                let comment = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                docLines.insert(comment, at: 0)
            } else if trimmed.hasPrefix("//") {
                let comment = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                docLines.insert(comment, at: 0)
            } else if trimmed.hasPrefix("*") || trimmed.hasPrefix("/**") || trimmed == "*/" {
                let comment =
                    trimmed
                    .replacingOccurrences(of: "/**", with: "")
                    .replacingOccurrences(of: "*/", with: "")
                    .replacingOccurrences(of: "* ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !comment.isEmpty {
                    docLines.insert(comment, at: 0)
                }
            } else {
                break
            }
            i -= 1
        }
        let result = docLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? nil : String(result.prefix(500))
    }

    /// Extract Python docstring (triple-quoted string after def/class line)
    static func extractPythonDocstring(lines: [String], afterLine: Int) -> String? {
        let nextIdx = afterLine + 1
        guard nextIdx < lines.count else { return nil }
        let trimmed = lines[nextIdx].trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\"\"\"") || trimmed.hasPrefix("'''") else { return nil }
        let quote = trimmed.hasPrefix("\"\"\"") ? "\"\"\"" : "'''"
        // Single-line docstring
        if trimmed.hasSuffix(quote) && trimmed.count > 6 {
            let inner = trimmed.dropFirst(3).dropLast(3)
            return String(inner).trimmingCharacters(in: .whitespaces)
        }
        // Multi-line docstring
        var docLines: [String] = []
        let firstContent = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        if !firstContent.isEmpty { docLines.append(firstContent) }
        for j in (nextIdx + 1)..<min(lines.count, nextIdx + 20) {
            let line = lines[j].trimmingCharacters(in: .whitespaces)
            if line.contains(quote) {
                let before = line.components(separatedBy: quote).first ?? ""
                if !before.trimmingCharacters(in: .whitespaces).isEmpty {
                    docLines.append(before.trimmingCharacters(in: .whitespaces))
                }
                break
            }
            docLines.append(line)
        }
        let result = docLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? nil : String(result.prefix(500))
    }

    // MARK: - Swift-specific helpers

    /// Extract inheritance/conformance from Swift type declaration
    static func extractSwiftInheritance(from line: String, afterName name: String) -> [String] {
        // Look for ": SomeType, SomeProtocol" after the name
        guard
            let nameRange = line.range(of: name),
            let colonRange = line.range(
                of: ":", range: nameRange.upperBound..<line.endIndex)
        else {
            return []
        }
        let afterColon = String(line[colonRange.upperBound...])
        let beforeBrace = afterColon.components(separatedBy: "{").first ?? afterColon
        let beforeWhere = beforeBrace.components(separatedBy: "where").first ?? beforeBrace
        return
            beforeWhere
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.first?.isLetter == true }
    }

    /// Extract generic parameters (<T, U>) from a declaration line
    static func extractGenericParams(from line: String) -> [String] {
        guard let openIdx = line.firstIndex(of: "<") else { return [] }
        var depth = 0
        var end = openIdx
        for i in line[openIdx...].indices {
            if line[i] == "<" {
                depth += 1
            } else if line[i] == ">" {
                depth -= 1
                if depth == 0 {
                    end = i
                    break
                }
            }
        }
        guard end > openIdx else { return [] }
        let inner = String(line[line.index(after: openIdx)..<end])
        return inner.components(separatedBy: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ":")
                    .first ?? ""
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Extract Swift annotations (@MainActor, @Sendable, etc.)
    static func extractAnnotations(from line: String) -> [String] {
        let pattern = #"@(\w+(?:\([^)]*\))?)"#
        return matchAll(pattern: pattern, in: line, group: 0)
    }

    // MARK: - Access Level Parsing

    static func parseAccessLevel(from groups: [String]) -> AccessLevel {
        for g in groups {
            switch g {
            case "open": return .open
            case "public": return .public
            case "internal": return .internal
            case "fileprivate": return .fileprivate
            case "private": return .private
            default: continue
            }
        }
        return .internal
    }

    static func parseJavaAccess(_ raw: String?) -> AccessLevel {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return .internal
        }
        switch raw {
        case "public": return .public
        case "protected": return .fileprivate
        case "private": return .private
        default: return .internal
        }
    }

    static func parseCSharpAccess(_ raw: String?) -> AccessLevel {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return .internal
        }
        switch raw {
        case "public": return .public
        case "protected": return .fileprivate
        case "private": return .private
        case "internal": return .internal
        default: return .internal
        }
    }

    // MARK: - Hashing

    /// FNV-1a hash for fast content change detection
    static func fnv1aHash(_ data: Data) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}
