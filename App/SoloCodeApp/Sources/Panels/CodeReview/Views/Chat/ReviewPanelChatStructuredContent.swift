import Foundation

enum ReviewPanelChatStructuredSectionStyle: Equatable, Codable {
    case prose
    case metadata
    case findings
    case log
}

struct ReviewPanelChatStructuredSection: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let lines: [String]
    let style: ReviewPanelChatStructuredSectionStyle
    let isInitiallyExpanded: Bool

    var displayLines: [ReviewPanelChatStructuredDisplayLine] {
        lines.enumerated().map { index, line in
            ReviewPanelChatStructuredDisplayLine(
                id: "\(id)-line-\(index)",
                text: line
            )
        }
    }
}

struct ReviewPanelChatStructuredDisplayLine: Identifiable, Equatable, Codable {
    let id: String
    let text: String
}

enum ReviewPanelChatStructuredContent {
    static func sections(for message: ReviewPanelMessage) -> [ReviewPanelChatStructuredSection] {
        switch message.kind {
        case .summary:
            return summarySections(from: message.content)
        case .reviewRun:
            return reviewRunSections(from: message.content, isStreaming: message.isStreaming)
        default:
            return []
        }
    }

    private static func summarySections(from content: String) -> [ReviewPanelChatStructuredSection] {
        let lines = normalizedLines(from: content)
        guard !lines.isEmpty else { return [] }

        var overview: [String] = []
        var metadata: [String] = []
        var findings: [String] = []

        for line in lines {
            if line.hasPrefix("## ") { continue }
            if line.hasPrefix("- [") {
                findings.append(cleanListPrefix(line))
            } else if line.hasPrefix("- ") {
                metadata.append(cleanListPrefix(line))
            } else {
                overview.append(line)
            }
        }

        var sections: [ReviewPanelChatStructuredSection] = []
        if !overview.isEmpty {
            sections.append(
                ReviewPanelChatStructuredSection(
                    id: "overview",
                    title: "Overview",
                    lines: overview,
                    style: .prose,
                    isInitiallyExpanded: true
                )
            )
        }
        if !metadata.isEmpty {
            sections.append(
                ReviewPanelChatStructuredSection(
                    id: "metadata",
                    title: "Session",
                    lines: metadata,
                    style: .metadata,
                    isInitiallyExpanded: true
                )
            )
        }
        if !findings.isEmpty {
            sections.append(
                ReviewPanelChatStructuredSection(
                    id: "findings",
                    title: "Findings",
                    lines: findings,
                    style: .findings,
                    isInitiallyExpanded: findings.count <= 6
                )
            )
        }
        return sections
    }

    private static func reviewRunSections(
        from content: String,
        isStreaming: Bool
    ) -> [ReviewPanelChatStructuredSection] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let parts = trimmed.components(separatedBy: "\n---\n")
        let logPart: String
        let verdictPart: String

        if parts.count > 1 {
            logPart = parts.dropLast().joined(separator: "\n---\n")
            verdictPart = parts.last ?? ""
        } else if let range = trimmed.range(of: "**Multi-swarm code review complete.**") {
            logPart = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            verdictPart = String(trimmed[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            logPart = trimmed
            verdictPart = ""
        }

        var sections = reviewRunLogSections(from: logPart, isStreaming: isStreaming)

        let verdictLines = normalizedLines(from: verdictPart)
        if !verdictLines.isEmpty {
            sections.append(
                ReviewPanelChatStructuredSection(
                    id: "verdict",
                    title: "Verdict",
                    lines: verdictLines,
                    style: .prose,
                    isInitiallyExpanded: true
                )
            )
        }
        return sections
    }

    private static func reviewRunLogSections(
        from logPart: String,
        isStreaming: Bool
    ) -> [ReviewPanelChatStructuredSection] {
        let logLines = normalizedLines(from: logPart)
        guard !logLines.isEmpty else { return [] }

        var sections: [ReviewPanelChatStructuredSection] = []
        var currentTitle: String?
        var currentLines: [String] = []

        func flushCurrentSection() {
            guard let currentTitle, !currentLines.isEmpty else { return }
            let sectionId = uniqueSectionID(
                for: currentTitle,
                existingCount: sections.count
            )
            sections.append(
                ReviewPanelChatStructuredSection(
                    id: sectionId,
                    title: currentTitle,
                    lines: currentLines,
                    style: currentTitle == "Planned Work" ? .findings : .log,
                    isInitiallyExpanded: isStreaming || currentLines.count <= 8
                )
            )
            currentLines = []
        }

        for line in logLines {
            if line.hasPrefix("### ") {
                flushCurrentSection()
                currentTitle = String(line.dropFirst(4))
            } else {
                if currentTitle == nil {
                    currentTitle = isStreaming ? "Live Output" : "Run Output"
                }
                currentLines.append(line)
            }
        }
        flushCurrentSection()
        return sections
    }

    private static func normalizedLines(from content: String) -> [String] {
        content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func cleanListPrefix(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("- ") else { return trimmed }
        return String(trimmed.dropFirst(2))
    }

    private static func uniqueSectionID(
        for title: String,
        existingCount: Int
    ) -> String {
        let normalizedTitle = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "\(normalizedTitle)-\(existingCount)"
    }
}
