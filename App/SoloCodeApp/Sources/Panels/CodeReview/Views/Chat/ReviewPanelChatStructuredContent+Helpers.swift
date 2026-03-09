import Foundation

// MARK: - Shared Helpers

extension ReviewPanelChatStructuredContent {
    static func normalizedLines(
        from content: String
    ) -> [String] {
        content
            .components(separatedBy: .newlines)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    static func cleanListPrefix(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard trimmed.hasPrefix("- ") else { return trimmed }
        return String(trimmed.dropFirst(2))
    }

    static func uniqueSectionID(
        for title: String,
        existingCount: Int
    ) -> String {
        let normalizedTitle = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "\(normalizedTitle)-\(existingCount)"
    }

    static func extractTaggedBlocks(
        from content: String,
        tag: String
    ) -> (blocks: [String], remainder: String) {
        let pattern = "<\(tag)>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: .caseInsensitive
        ) else {
            return ([], content)
        }

        let nsContent = content as NSString
        let matches = regex.matches(
            in: content,
            range: NSRange(
                location: 0,
                length: nsContent.length
            )
        )

        var blocks: [String] = []
        for match in matches {
            if match.numberOfRanges >= 2 {
                let block = nsContent
                    .substring(with: match.range(at: 1))
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                if !block.isEmpty {
                    blocks.append(block)
                }
            }
        }

        let stripped = regex
            .stringByReplacingMatches(
                in: content,
                range: NSRange(
                    location: 0,
                    length: nsContent.length
                ),
                withTemplate: ""
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (blocks, stripped)
    }
}
