import Foundation

// MARK: - Summary Sections

extension ReviewPanelChatStructuredContent {
    static func summarySections(
        from content: String
    ) -> [ReviewPanelChatStructuredSection] {
        // Extract mermaid blocks first
        let mermaidBlocks = MermaidExtractor.extractMermaidBlocks(
            from: content
        )
        let cleaned = mermaidBlocks.isEmpty
            ? content
            : MermaidExtractor.stripMermaidBlocks(from: content)

        let lines = normalizedLines(from: cleaned)
        guard !lines.isEmpty else { return [] }

        var overview: [String] = []
        var metadata: [String] = []
        var findings: [String] = []
        var outcomeLine: String?

        for line in lines {
            if line.hasPrefix("## ") { continue }
            if line.lowercased().hasPrefix("- outcome:") {
                outcomeLine = cleanListPrefix(line)
            } else if line.hasPrefix("- [") {
                findings.append(cleanListPrefix(line))
            } else if line.hasPrefix("- ") {
                metadata.append(cleanListPrefix(line))
            } else {
                overview.append(line)
            }
        }

        var sections: [ReviewPanelChatStructuredSection] = []

        // Outcome card at the top
        if let outcomeLine {
            var outcomeLines = [outcomeLine]
            outcomeLines.append(contentsOf: metadata)
            sections.append(
                ReviewPanelChatStructuredSection(
                    id: "outcome",
                    title: "Outcome",
                    lines: outcomeLines,
                    style: .outcome,
                    isInitiallyExpanded: true
                )
            )
        }

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
        if !metadata.isEmpty, outcomeLine == nil {
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

        // Mermaid diagrams at the end
        for (index, block) in mermaidBlocks.enumerated() {
            let diagramLines = block
                .components(separatedBy: .newlines)
                .filter {
                    !$0.trimmingCharacters(in: .whitespaces).isEmpty
                }
            guard !diagramLines.isEmpty else { continue }
            sections.append(
                ReviewPanelChatStructuredSection(
                    id: "mermaid-\(index)",
                    title: "Diagram",
                    lines: diagramLines,
                    style: .mermaid,
                    isInitiallyExpanded: true
                )
            )
        }
        return sections
    }
}
