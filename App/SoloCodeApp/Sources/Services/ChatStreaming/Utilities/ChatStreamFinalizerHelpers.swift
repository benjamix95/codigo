import Foundation

// MARK: - Pending stream policy

func shouldDiscardPendingStreamSnapshot(
    targetConversationId: UUID?,
    pendingConversationId: UUID?
) -> Bool {
    guard let targetConversationId else { return true }
    return pendingConversationId == targetConversationId
}

// MARK: - Reasoning text merge (single source of truth)

enum ChatStreamReasoningTextMerge {
    /// Merge incrementali di reasoning da stream / bridge; cap e sanitizzazione allineati al ChatStore.
    static func merge(existing: String?, incoming: String) -> String {
        let incomingTrimmed = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incomingTrimmed.isEmpty else {
            return ChatStore.sanitizedChatReasoningText(existing ?? "")
        }
        guard let existing, !existing.isEmpty else {
            return ChatStore.sanitizedChatReasoningText(String(incomingTrimmed.prefix(24_000)))
        }

        if incomingTrimmed == existing { return ChatStore.sanitizedChatReasoningText(existing) }
        if incomingTrimmed.hasPrefix(existing) {
            return ChatStore.sanitizedChatReasoningText(String(incomingTrimmed.prefix(24_000)))
        }
        if existing.hasPrefix(incomingTrimmed) || existing.contains(incomingTrimmed) {
            return ChatStore.sanitizedChatReasoningText(existing)
        }
        if incomingTrimmed.contains(existing) {
            return ChatStore.sanitizedChatReasoningText(String(incomingTrimmed.prefix(24_000)))
        }

        let overlap = suffixPrefixOverlapLength(lhs: existing, rhs: incomingTrimmed)
        if overlap > 0 {
            let suffixStart = incomingTrimmed.index(incomingTrimmed.startIndex, offsetBy: overlap)
            let merged = existing + String(incomingTrimmed[suffixStart...])
            return ChatStore.sanitizedChatReasoningText(String(merged.suffix(24_000)))
        }

        let merged = existing + "\n\n" + incomingTrimmed
        return ChatStore.sanitizedChatReasoningText(String(merged.suffix(24_000)))
    }

    static func suffixPrefixOverlapLength(lhs: String, rhs: String) -> Int {
        let maxOverlap = min(lhs.count, rhs.count, 1_024)
        guard maxOverlap > 0 else { return 0 }
        for size in stride(from: maxOverlap, through: 1, by: -1) {
            if lhs.suffix(size) == rhs.prefix(size) {
                return size
            }
        }
        return 0
    }
}

// MARK: - UI gating

enum ChatStreamFinalizerUIDecisions {
    static func shouldShowFinalChatActions(
        conversation: Conversation?,
        isLoadingForCurrentConversation: Bool
    ) -> Bool {
        guard !isLoadingForCurrentConversation else { return false }
        guard let conversation else { return false }
        guard conversation.messages.contains(where: { $0.role == .assistant }) else { return false }
        guard let lastMessage = conversation.messages.last else { return false }
        return lastMessage.role == .assistant && !lastMessage.isStreaming
    }
}
