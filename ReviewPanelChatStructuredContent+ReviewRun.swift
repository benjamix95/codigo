import Foundation

// MARK: - Review Run Sections

extension ReviewPanelChatStructuredContent {
    static func reviewRunSections(
        from content: String,
        isStreaming: Bool
    ) -> [ReviewPanelChatStructuredSection] {
        let trimmed = content.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return [] }

        let parts = trimmed.components(separatedBy: "\n---\n")
        let logPart: String
        let verdictPart: String

        if parts.count > 1 {
            logPart = parts.dropLast()
                .joined(separator: "\n---\n")
            verdictPart = parts.last ?? ""
        } else if let range = trimmed.range(
            of: "**Multi-swarm code review complete.**"
        ) {
            logPart = String(trimmed[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            verdictPart = String(trimmed[range.lowerBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            logPart = trimmed
            verdictPart = ""
        }

        var sections = reviewRunLogSections(
            from: logPart, isStreaming: isStreaming
        )

        // Parse verdict: extract mermaid, then prose/outcome
        if !verdictPart.isEmpty {
            sections.append(
                contentsOf: reviewRunVerdictSections(from: verdictPart)
            )
        }
        return sections
    }

    // MARK: - Verdict Parsing

    private static func reviewRunVerdictSections(
        from verdictPart: String
    ) -> [ReviewPanelChatStructuredSection] {
        var sections: [ReviewPanelChatStructuredSection] = []
        var remainder = verdictPart

        // Extract mermaid diagrams from verdict
        let mermaidBlocks = MermaidExtractor.extractMermaidBlocks(
            from: remainder
        )
        if !mermaidBlocks.isEmpty {
            remainder = MermaidExtractor.stripMermaidBlocks(
                from: remainder
            )
        }

        // Extract <outcome> tags from verdict
        let outcomeResult = extractTaggedBlocks(
            from: remainder, tag: "outcome"
        )
        if !outcomeResult.blocks.isEmpty {
            remainder = outcomeResult.remainder
        }

        // Remaining verdict text → outcome-styled card
        let verdictLines = normalizedLines(from: remainder)
        if !verdictLines.isEmpty {
            sections.append(
                ReviewPanelChatStructuredSection(
                    id: "verdict",
                    title: "Verdict",
                    lines: verdictLines,
                    style: .outcome,
                    isInitiallyExpanded: true
                )
            )
        }

        // Explicit <outcome> blocks
        for (index, block) in outcomeResult.blocks.enumerated() {
            let lines = normalizedLines(from: block)
            guard !lines.isEmpty else { continue }
            sections.append(
                ReviewPanelChatStructuredSection(
                    id: "outcome-\(index)",
                    title: "Outcome",
                    lines: lines,
                    style: .outcome,
                    isInitiallyExpanded: true
                )
            )
        }

        // Mermaid diagrams at the end
        for (index, block) in mermaidBlocks.enumerated() {
            let lines = block
                .components(separatedBy: .newlines)
                .filter {
                    !$0.trimmingCharacters(in: .whitespaces).isEmpty
                }
            guard !lines.isEmpty else { continue }
            sections.append(
                ReviewPanelChatStructuredSection(
                    id: "mermaid-\(index)",
                    title: "Diagram",
                    lines: lines,
                    style: .mermaid,
                    isInitiallyExpanded: true
                )
            )
        }

        return sections
    }

    // MARK: - Log Section Parsing

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
            guard let title = currentTitle,
                  !currentLines.isEmpty
            else { return }
            let sectionId = uniqueSectionID(
                for: title,
                existingCount: sections.count
            )
            let style = sectionStyle(for: title)
            let expanded = sectionExpanded(
                style: style,
                lineCount: currentLines.count,
                isStreaming: isStreaming
            )
            sections.append(
                ReviewPanelChatStructuredSection(
                    id: sectionId,
                    title: title,
                    lines: currentLines,
                    style: style,
                    isInitiallyExpanded: expanded
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
                    currentTitle = isStreaming
                        ? "Live Output" : "Run Output"
                }
                currentLines.append(line)
            }
        }
        flushCurrentSection()
        return sections
    }

    // MARK: - Section Style Mapping

    private static func sectionStyle(
        for title: String
    ) -> ReviewPanelChatStructuredSectionStyle {
        let lower = title.lowercased()
        if lower == "thinking" || lower == "thought process"
            || lower == "reasoning"
        {
            return .thinking
        }
        if lower == "activity" || lower == "progress"
            || lower == "audit"
        {
            return .activity
        }
        if lower == "planned work" {
            return .findings
        }
        if lower == "response" {
            return .prose
        }
        return .log
    }

    private static func sectionExpanded(
        style: ReviewPanelChatStructuredSectionStyle,
        lineCount: Int,
        isStreaming: Bool
    ) -> Bool {
        switch style {
        case .thinking:
            return false
        case .activity:
            return isStreaming
        case .findings:
            return isStreaming || lineCount <= 8
        default:
            return isStreaming || lineCount <= 8
        }
    }
}
