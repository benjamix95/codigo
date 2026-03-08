import Foundation

// MARK: - Mermaid Diagram Extraction

enum MermaidExtractor {
    // Compiled once, reused on every call
    private static let extractRegex: NSRegularExpression? =
        try? NSRegularExpression(
            pattern: "```mermaid\\b\\s*(?:\\r?\\n)?([\\s\\S]*?)```",
            options: .caseInsensitive
        )
    private static let stripRegex: NSRegularExpression? =
        try? NSRegularExpression(
            pattern: "```mermaid\\b\\s*(?:\\r?\\n)?[\\s\\S]*?```",
            options: .caseInsensitive
        )

    static func extractFirstMermaidBlock(from markdown: String) -> String? {
        guard let regex = extractRegex else { return nil }
        let nsString = markdown as NSString
        let match = regex.firstMatch(
            in: markdown,
            range: NSRange(location: 0, length: nsString.length)
        )
        guard let blockMatch = match, blockMatch.numberOfRanges >= 2 else { return nil }
        let block = nsString.substring(with: blockMatch.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !block.isEmpty else { return nil }
        return block
    }

    static func extractMermaidBlocks(from markdown: String) -> [String] {
        guard let regex = extractRegex else { return [] }
        let nsString = markdown as NSString
        let results = regex.matches(in: markdown, range: NSRange(location: 0, length: nsString.length))
        var blocks: [String] = []
        blocks.reserveCapacity(results.count)
        for match in results {
            if match.numberOfRanges >= 2 {
                let block = nsString.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !block.isEmpty { blocks.append(block) }
            }
        }
        return blocks
    }

    static func stripMermaidBlocks(from markdown: String) -> String {
        guard let regex = stripRegex else { return markdown }
        let nsString = markdown as NSString
        return regex.stringByReplacingMatches(
            in: markdown,
            range: NSRange(location: 0, length: nsString.length),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    var htmlEscapedForMermaid: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
