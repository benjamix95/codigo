import Foundation

extension ChatMessage {
    var resolvedPrimaryText: String {
        let text = primaryTextSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            return text
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedTimelineBlocks: [PersistedChatTimelineBlock] {
        if let blocks, !blocks.isEmpty {
            return blocks
        }

        var derived: [PersistedChatTimelineBlock] = [
            PersistedChatTimelineBlock(
                id: "primary-text",
                kind: .primaryText,
                text: resolvedPrimaryText
            ),
        ]

        if let reasoningText {
            let trimmed = reasoningText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                derived.append(
                    PersistedChatTimelineBlock(
                        id: "reasoning",
                        kind: .reasoning,
                        title: "Thinking",
                        text: trimmed,
                        isCollapsible: true,
                        isCollapsedByDefault: true
                    )
                )
            }
        }

        return derived.filter { !$0.text.isEmpty || !$0.items.isEmpty }
    }

    var exportMarkdownContent: String {
        let timelineBlocks = resolvedTimelineBlocks
        guard !timelineBlocks.isEmpty else {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var lines: [String] = []
        for block in timelineBlocks {
            switch block.kind {
            case .primaryText:
                if !block.text.isEmpty {
                    lines.append(block.text)
                }
            case .reasoning:
                if !block.text.isEmpty {
                    lines.append("### Thinking")
                    lines.append(block.text)
                }
            case .mermaid:
                lines.append("### \(block.title ?? "Diagram")")
                lines.append("```mermaid")
                lines.append(block.text)
                lines.append("```")
            case .commands, .files:
                lines.append("### \(block.title ?? "Details")")
                for item in block.items {
                    lines.append("- \(item)")
                }
            case .status, .plan, .toolTrace:
                lines.append("### \(block.title ?? "Details")")
                if !block.text.isEmpty {
                    lines.append(block.text)
                }
                for item in block.items {
                    lines.append("- \(item)")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
