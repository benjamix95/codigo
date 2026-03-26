import Foundation

extension ChatPanelView {
    static func mergeReasoningText(existing: String?, incoming: String) -> String {
        ChatStreamReasoningTextMerge.merge(existing: existing, incoming: incoming)
    }

    static func reasoningSuffixPrefixOverlapLength(lhs: String, rhs: String) -> Int {
        ChatStreamReasoningTextMerge.suffixPrefixOverlapLength(lhs: lhs, rhs: rhs)
    }

    static func shouldShowFinalChatActions(
        conversation: Conversation?,
        isLoadingForCurrentConversation: Bool
    ) -> Bool {
        ChatStreamFinalizerUIDecisions.shouldShowFinalChatActions(
            conversation: conversation,
            isLoadingForCurrentConversation: isLoadingForCurrentConversation
        )
    }
}
