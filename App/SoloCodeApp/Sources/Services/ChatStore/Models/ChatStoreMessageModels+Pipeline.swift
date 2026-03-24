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
            // If blocks exist but their primary text is empty while
            // the message content is not, substitute the content into
            // the primary text block.  This prevents artifact-only
            // pipeline commits from hiding inline text written by
            // the assistant_update / stream_replace_text fallback.
            let primaryEmpty = !blocks.contains(where: {
                $0.kind == .primaryText && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
            if primaryEmpty {
                let fallbackText = resolvedPrimaryText
                if !fallbackText.isEmpty {
                    var fixed = blocks
                    if let idx = fixed.firstIndex(where: { $0.kind == .primaryText }) {
                        fixed[idx] = PersistedChatTimelineBlock(
                            id: fixed[idx].id,
                            kind: .primaryText,
                            text: fallbackText
                        )
                    } else {
                        fixed.insert(
                            PersistedChatTimelineBlock(
                                id: "primary-text",
                                kind: .primaryText,
                                text: fallbackText
                            ),
                            at: 0
                        )
                    }
                    return fixed
                }
            }
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
            case .toolMarker:
                break // Placeholder — no content to render
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
