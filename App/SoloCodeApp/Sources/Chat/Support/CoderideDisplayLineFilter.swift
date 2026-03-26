import Foundation

/// Filtra righe “solo nome tool” (`coderide_*`, prefissi MCP) dalla prose mostrata in chat; i blocchi ``` restano invariati.
enum CoderideDisplayLineFilter {
    static func stripDisplayLinesWithCoderideToolPrefix(_ content: String) -> String {
        splitByCodeFences(content).map { segment, isCode in
            if isCode { return segment }
            return segment
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !shouldHideLine(String($0)) }
                .joined(separator: "\n")
        }.joined()
    }

    private static func shouldHideLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        let payload: String
        if trimmed.hasPrefix("- ") {
            payload = String(trimmed.dropFirst(2))
        } else if trimmed.hasPrefix("* ") {
            payload = String(trimmed.dropFirst(2))
        } else if trimmed.hasPrefix("+ ") {
            payload = String(trimmed.dropFirst(2))
        } else {
            payload = trimmed
        }
        let core = payload.trimmingCharacters(in: .whitespaces)
        if core.isEmpty { return false }
        let lower = core.lowercased()
        if lower.contains("[policy error]") { return true }
        if lower.contains("[coderide") { return true }
        if lower.hasPrefix("coderide_") { return true }
        if lower.hasPrefix("mcp__coderide__coderide_") { return true }
        if lower.hasPrefix("functions.mcp__coderide__coderide_") { return true }
        if lower.hasPrefix("functions.coderide_") { return true }
        return false
    }

    private static func splitByCodeFences(_ input: String) -> [(String, Bool)] {
        var segments: [(String, Bool)] = []
        var cursor = input.startIndex
        while let openRange = input[cursor...].range(of: "```") {
            let start = openRange.lowerBound
            if start > cursor {
                segments.append((String(input[cursor..<start]), false))
            }
            let afterOpen = input.index(start, offsetBy: 3)
            guard afterOpen < input.endIndex else {
                segments.append((String(input[start...]), true))
                return segments
            }
            if let closeRange = input[afterOpen...].range(of: "```") {
                let end = closeRange.upperBound
                segments.append((String(input[start..<end]), true))
                cursor = end
            } else {
                segments.append((String(input[start...]), true))
                return segments
            }
        }
        if cursor < input.endIndex {
            segments.append((String(input[cursor...]), false))
        }
        return segments
    }
}
