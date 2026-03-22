import CoderEngine
import Foundation

/// Swift fallback for extracting structured review findings from chat
/// messages when the Rust bridge is unavailable or returns nil.
enum ReviewPanelChatFindingsSwiftFallback {
    static func extract(
        content: String,
        existing: [CodeReviewFinding],
        currentSnapshot: CodeReviewSessionSnapshot
    ) -> ReviewCoreChatExtractionPayload? {
        guard let blockStart = content.range(of: "```review_findings"),
              let blockEnd = content.range(
                of: "```",
                range: blockStart.upperBound..<content.endIndex
              ) else {
            return nil
        }

        let jsonSlice = content[blockStart.upperBound..<blockEnd.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonSlice.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(
                ChatFindingsBlock.self, from: data
              ) else {
            return nil
        }

        let existingKeys = Set(existing.map { deduplicationKey(for: $0) })
        var merged = existing
        var insertedCount = 0

        for raw in parsed.findings {
            let finding = CodeReviewFinding(
                id: UUID().uuidString.lowercased(),
                severity: FindingSeverity(rawValue: raw.severity) ?? .warning,
                category: FindingCategory(rawValue: raw.category) ?? .correctness,
                filePath: raw.file,
                lineNumber: raw.line,
                message: raw.message,
                suggestedFix: raw.suggestedFix
            )
            let key = deduplicationKey(for: finding)
            guard !existingKeys.contains(key) else { continue }
            merged.append(finding)
            insertedCount += 1
        }

        let blockEndIdx: String.Index = {
            let afterClose = content.index(
                blockEnd.upperBound,
                offsetBy: 0,
                limitedBy: content.endIndex
            ) ?? content.endIndex
            if afterClose < content.endIndex,
               content[afterClose] == "\n" {
                return content.index(after: afterClose)
            }
            return afterClose
        }()
        let visibleContent = String(
            content[content.startIndex..<blockStart.lowerBound]
        ) + String(
            content[blockEndIdx..<content.endIndex]
        )

        return ReviewCoreChatExtractionPayload(
            foundBlock: true,
            visibleContent: visibleContent
                .trimmingCharacters(in: .whitespacesAndNewlines),
            findings: merged,
            insertedCount: insertedCount,
            extractedCount: parsed.findings.count,
            snapshot: nil
        )
    }

    private static func deduplicationKey(
        for finding: CodeReviewFinding
    ) -> String {
        "\(finding.filePath):\(finding.lineNumber ?? 0):\(finding.message)"
    }
}

private struct ChatFindingsBlock: Decodable {
    let findings: [ChatFindingEntry]
}

private struct ChatFindingEntry: Decodable {
    let severity: String
    let category: String
    let file: String
    let line: Int?
    let message: String
    let suggestedFix: String?

    enum CodingKeys: String, CodingKey {
        case severity, category, file, line, message
        case suggestedFix = "suggested_fix"
    }
}
