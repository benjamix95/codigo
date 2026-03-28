import Foundation

/// Segnali markdown che spesso duplicano la checklist todo mostrata nel composer.
enum ChatTodoMarkdownInspection {
    static func hasGitHubStyleTaskList(_ text: String) -> Bool {
        text.range(
            of: #"(?m)^\s*[-*]\s*\[[ xX]?\]\s+"#,
            options: .regularExpression
        ) != nil
    }

    static func hasOrderedListLines(_ text: String) -> Bool {
        text.range(
            of: #"(?m)^\s*\d+\.\s+\S"#,
            options: .regularExpression
        ) != nil
    }

    static func hasStructuredPlanOrTodoHeader(_ text: String) -> Bool {
        text.range(
            of: #"(?im)^\s*##\s*(?:plan|piano|todo|to-do|questions?|clarification|option(?:s)?)\b"#,
            options: .regularExpression
        ) != nil
    }

    /// Testo unificato blocchi timeline “testuali” visibili (primaryText + markdown artifact).
    static func combinedVisibleTextualPayload(for message: ChatMessage) -> String {
        let blocks = ChatTurnTimelineOrdering.visibleBlocks(from: message.resolvedTimelineBlocks)
        var chunks: [String] = []
        for b in blocks {
            switch b.kind {
            case .primaryText, .plan, .status, .reasoning:
                if !b.text.isEmpty { chunks.append(b.text) }
            default:
                break
            }
        }
        let primary = message.resolvedPrimaryText
        if !primary.isEmpty {
            chunks.append(primary)
        }
        return chunks.joined(separator: "\n\n")
    }
}
