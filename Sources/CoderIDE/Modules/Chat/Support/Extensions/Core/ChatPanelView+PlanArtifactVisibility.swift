import CoderEngine
import Foundation

extension ChatPanelView {
    func hasActivePlanContext(for streamConversationId: UUID?) -> Bool {
        let hasPlanBoardForStreamConversation: Bool = {
            guard let streamConversationId else { return false }
            return chatStore.planBoard(for: streamConversationId) != nil
        }()
        let hasPlanBoardForCurrentConversation: Bool = {
            guard let currentConversationId = conversationId else { return false }
            return chatStore.planBoard(for: currentConversationId) != nil
        }()
        return shouldTreatConversationAsPlanContext(
            coderMode: coderMode,
            hasInlinePlanSession: hasInlinePlanSession,
            hasActivePlanFlowPhase: hasActivePlanFlowPhase,
            streamConversationId: streamConversationId,
            currentConversationId: conversationId,
            hasPlanBoardForStreamConversation: hasPlanBoardForStreamConversation,
            hasPlanBoardForCurrentConversation: hasPlanBoardForCurrentConversation,
            showPlanPanel: showPlanPanel,
            activeBuildPlanConversationId: activeBuildPlanConversationId
        )
    }

    func looksLikePlanPayload(_ rawText: String) -> Bool {
        let cleaned = ChatStore
            .stripCoderideMarkers(rawText, aggressive: false)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }

        let lower = cleaned.lowercased()
        let hasPlanSignalToken =
            lower.contains("## plan")
            || lower.contains("## questions")
            || lower.contains("## option")
            || lower.contains("## todo")
            || lower.contains("```mermaid")
            || lower.contains("- [")
        guard hasPlanSignalToken else { return false }

        let hasPlanLikeHeader = cleaned.range(
            of: #"(?im)^\s*##\s*(?:plan|questions?|clarification|option(?:s)?|todo|to-do)\b"#,
            options: .regularExpression
        ) != nil
        if hasPlanLikeHeader { return true }

        if PlanOptionsParser.hasRequiredTodoHeader(cleaned) { return true }

        let hasChecklist = cleaned.range(
            of: #"(?im)^\s*[-*]\s*\[[ xX]?\]\s+"#,
            options: .regularExpression
        ) != nil
        let hasMermaid = cleaned.range(
            of: #"(?im)^\s*```mermaid\b"#,
            options: .regularExpression
        ) != nil
        return hasChecklist || hasMermaid
    }

    func shouldSuppressPlanArtifactsInChat(
        message: ChatMessage,
        conversationId: UUID?
    ) -> Bool {
        guard message.role == .assistant else { return false }
        guard hasActivePlanContext(for: conversationId) else { return false }
        return looksLikePlanPayload(message.content)
    }

    func chatDisplayMessage(
        from message: ChatMessage,
        conversationId _: UUID?
    ) -> ChatMessage {
        var displayMessage = message
        displayMessage.content = planInPanelPlaceholder
        return displayMessage
    }

    var showsSwarmViewOnly: Bool { shouldShowSwarmViewOnly(for: coderMode) }

    var shouldShowFinalChatActions: Bool {
        Self.shouldShowFinalChatActions(
            conversation: chatStore.conversation(for: conversationId),
            isLoadingForCurrentConversation: isLoadingForCurrentConversation
        ) && !showsSwarmViewOnly
    }
}
