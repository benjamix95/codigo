import CoreGraphics
import Foundation

enum SubagentChatCardCompactPresentation {
    static let headerVerticalPadding: CGFloat = 8
    static let taskPromptCollapsedLineLimit = 1
    static let compactPreviewLineLimit = 2
    static let compactPreviewVerticalPadding: CGFloat = 6
    static let taskPromptVerticalPadding: CGFloat = 5
    static let liveTranscriptPreviewEntryLimit = 3
    static let completedTranscriptPreviewEntryLimit = 4
    static let expandedTranscriptMaxHeight: CGFloat = 280
    static let expandedSnapshotPreviewMaxHeight: CGFloat = 176

    static func compactPreviewText(from details: [String], suffixCount: Int) -> String? {
        let preview = details
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .suffix(suffixCount)
            .joined(separator: "\n")
        return preview.isEmpty ? nil : preview
    }

    static func compactPreviewText(from liveText: String, suffixCount: Int) -> String? {
        let lines = liveText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        return lines.suffix(suffixCount).joined(separator: "\n")
    }
}
