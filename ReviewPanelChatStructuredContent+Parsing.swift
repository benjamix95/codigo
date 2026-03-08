import Foundation

// MARK: - Content Parsing

enum ReviewPanelChatStructuredContent {
    static func sections(
        for message: ReviewPanelMessage
    ) -> [ReviewPanelChatStructuredSection] {
        switch message.kind {
        case .summary:
            return summarySections(from: message.content)
        case .reviewRun:
            return reviewRunSections(
                from: message.content,
                isStreaming: message.isStreaming
            )
        default:
            if message.role == .assistant {
                return assistantSections(from: message.content)
            }
            return []
        }
    }
}

// MARK: - Assistant Sections

extension ReviewPanelChatStructuredContent {
    static func assistantSections(
        from content: String
    ) -> [ReviewPanelChatStructuredSection] {
        let trimmed = content.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return [] }

        var sections: [ReviewPanelChatStructuredSection] = []
        var remainder = trimmed

        // 1. Extract <thinking> blocks
        let thinkingResult = extractTaggedBlocks(
            from: remainder, tag: "thinking"
        )
        for (index, block) in thinkingResult.blocks.enumerated() {
            let lines = normalizedLines(from: block)
            guard !lines.isEmpty else { continue }
            sections.append(
                ReviewPanelChatStructuredSection(
                    id: "thinking-\(index)",
                    title: "Thought Process",
                    lines: lines,
                    style: .thinking,
                    isInitiallyExpanded: false
                )
            )
        }
        remainder = thinkingResult.remainder

        // 2. Extract <activity> blocks
        let activityResult = extractTaggedBlocks(
            from: remainder, tag: "activity"
        )
        for (index, block) in activityResult.blocks.enumerated() {
            let lines = normalizedLines(from: block)
            guard !lines.isEmpty else { continue }
            sections.append(
                ReviewPanelChatStructuredSection(
                    id: "activity-\(index)",
                    title: "Activity",
                    lines: lines,
                    style: .activity,
                    isInitiallyExpanded: false
                )
            )
        }
        remainder = activityResult.remainder

        // 3. Extract ```mermaid blocks
        let mermaidBlocks = MermaidExtractor.extractMermaidBlocks(
            from: remainder
        )
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
        if !mermaidBlocks.isEmpty {
            remainder = MermaidExtractor.stripMermaidBlocks(
                from: remainder
            )
        }

        // 4. Extract <outcome> blocks
        let outcomeResult = extractTaggedBlocks(
            from: remainder, tag: "outcome"
        )
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
        remainder = outcomeResult.remainder

        // 5. Remaining text → prose response
        let responseLines = normalizedLines(from: remainder)
        if !responseLines.isEmpty {
            let insertAt = thinkingResult.blocks.isEmpty
                ? 0
                : min(thinkingResult.blocks.count, sections.count)
            sections.insert(
                ReviewPanelChatStructuredSection(
                    id: "response",
                    title: "Response",
                    lines: responseLines,
                    style: .prose,
                    isInitiallyExpanded: true
                ),
                at: insertAt
            )
        }

        return sections
    }
}
