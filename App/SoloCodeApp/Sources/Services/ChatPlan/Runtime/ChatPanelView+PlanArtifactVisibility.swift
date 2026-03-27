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

    /// Quando il composer mostra già i todo canonici del piano, nascondi il dump markdown del piano in timeline (anche se `shouldRoutePlanStreamingToPanel` è false).
    private func shouldHidePlanMarkdownForComposerTodoParity(
        conversationId: UUID,
        fullLooksLikePlanPayload: Bool
    ) -> Bool {
        guard fullLooksLikePlanPayload else { return false }
        let items = resolveComposerTodoItems(
            todoStore: todoStore,
            conversationId: conversationId,
            includeOperationalRuntimeTodos: false
        )
        return shouldShowComposerTodoOverlay(
            items: items,
            coderMode: coderMode,
            planToggleEnabled: planToggleEnabled,
            planFlowPhase: planFlowPhase,
            planningState: planningState
        )
    }

    /// Allineato a `handleStreamResult`: quando true, in chat si mostra solo `planInPanelPlaceholder` ma il messaggio in store conserva il testo completo.
    func planMarkdownHiddenInChat(
        effectiveFullText: String,
        conversationId: UUID,
        isBuildContext: Bool,
        shouldRunPlanInline: Bool
    ) -> Bool {
        let fullLooksLikePlanPayload = looksLikePlanPayload(effectiveFullText)
        let shouldRoutePlanStreamToPanel = shouldRoutePlanStream(to: conversationId)
        let shouldHidePlanMarkdownForBuild = isBuildContext && shouldRoutePlanStreamToPanel
        let hasPlanContextForStreamConversation = hasActivePlanContext(for: conversationId)
        let hiddenByRoute = shouldHidePlanMarkdownInChat(
            shouldRoutePlanStreamToPanel: shouldRoutePlanStreamToPanel,
            coderMode: coderMode,
            shouldRunPlanInline: shouldRunPlanInline,
            fullLooksLikePlanPayload: fullLooksLikePlanPayload,
            shouldHidePlanMarkdownForBuild: shouldHidePlanMarkdownForBuild,
            hasActivePlanContext: hasPlanContextForStreamConversation
        )
        let hiddenByComposerParity = shouldHidePlanMarkdownForComposerTodoParity(
            conversationId: conversationId,
            fullLooksLikePlanPayload: fullLooksLikePlanPayload
        )
        let hidden = hiddenByRoute || hiddenByComposerParity
        // #region agent log
        PlanFlowDebugNDJSONLog.append(
            hypothesisId: "J",
            location: "ChatPanelView+PlanArtifactVisibility.planMarkdownHiddenInChat",
            message: "plan_markdown_hidden_gate",
            data: [
                "conversationId": conversationId.uuidString.lowercased(),
                "hidden": hidden ? "1" : "0",
                "hiddenByRoute": hiddenByRoute ? "1" : "0",
                "hiddenByComposerParity": hiddenByComposerParity ? "1" : "0",
                "shouldRoutePlanStreamToPanel": shouldRoutePlanStreamToPanel ? "1" : "0",
                "shouldRoutePlanStreamingToPanel": shouldRoutePlanStreamingToPanel ? "1" : "0",
                "fullLooksLikePlanPayload": fullLooksLikePlanPayload ? "1" : "0",
                "isBuildContext": isBuildContext ? "1" : "0",
                "shouldHidePlanMarkdownForBuild": shouldHidePlanMarkdownForBuild ? "1" : "0",
                "hasActivePlanContext": hasPlanContextForStreamConversation ? "1" : "0",
                "shouldRunPlanInline": shouldRunPlanInline ? "1" : "0",
                "coderMode": String(describing: coderMode),
                "textLen": String(effectiveFullText.count),
            ]
        )
        // #endregion
        return hidden
    }

    func shouldSuppressPlanArtifactsInChat(
        message: ChatMessage,
        conversationId: UUID?
    ) -> Bool {
        guard message.role == .assistant else { return false }
        guard let conversationId else { return false }
        let isBuildContext = isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
        let suppress = planMarkdownHiddenInChat(
            effectiveFullText: message.content,
            conversationId: conversationId,
            isBuildContext: isBuildContext,
            shouldRunPlanInline: planShouldRunInline
        )
        // #region agent log
        PlanFlowDebugNDJSONLog.append(
            hypothesisId: "J",
            location: "ChatPanelView+PlanArtifactVisibility.shouldSuppressPlanArtifactsInChat",
            message: "suppress_plan_artifacts_assistant",
            data: [
                "conversationId": conversationId.uuidString.lowercased(),
                "messageId": message.id.uuidString.lowercased(),
                "suppress": suppress ? "1" : "0",
                "isBuildContext": isBuildContext ? "1" : "0",
                "blockCount": String(message.blocks?.count ?? 0),
            ]
        )
        // #endregion
        return suppress
    }

    func chatDisplayMessage(
        from message: ChatMessage,
        conversationId _: UUID?
    ) -> ChatMessage {
        var displayMessage = message
        displayMessage.content = planInPanelPlaceholder
        displayMessage.primaryTextSnapshot = planInPanelPlaceholder
        if var blocks = displayMessage.blocks, !blocks.isEmpty {
            displayMessage.blocks = blocks.compactMap { block in
                if block.kind == .plan {
                    return nil
                }
                if block.kind == .primaryText {
                    var updated = block
                    if looksLikePlanPayload(updated.text) || looksLikePlanPayload(message.content) {
                        updated.text = planInPanelPlaceholder
                    }
                    return updated
                }
                return block
            }
        }
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
