import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func messagesStack(for conv: Conversation) -> some View {
        let convId = conv.id
        let messages = conv.messages
        let lastMsg = messages.last
        let hasPersistentPlanCard = messages.contains { $0.planAttachment != nil }
        let latestVisibleAssistantMessageId = messages.last(where: {
            $0.role == .assistant && !shouldHideBuildKickoffMessage($0, in: convId)
        })?.id
        let latestAssistantMessageIdWithTrace = messages.last(where: { message in
            guard message.role == .assistant else { return false }
            guard !shouldHideBuildKickoffMessage(message, in: convId) else { return false }
            return toolTraceStore.hasTrace(
                conversationId: convId,
                assistantMessageId: message.id
            )
        })?.id
        let todoCardAssistantMessageId = resolveTodoCardAssistantMessageId(
            messages: messages,
            activeAssistantMessageId: activeToolTraceTurnsByConversation[convId]?.assistantMessageId,
            latestAssistantMessageIdWithTrace: latestAssistantMessageIdWithTrace,
            pipelineAssistantMessageId: currentAssistantPipelineTarget(for: convId)?.messageId,
            latestVisibleAssistantMessageId: latestVisibleAssistantMessageId
        )
        let messageIndexById: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: messages.enumerated().map { ($0.element.id, $0.offset) }
        )
        return LazyVStack(alignment: .leading, spacing: 28) {
            Color.clear
                .frame(height: 1)
                .id(chatScrollTopAnchorId)
            ForEach(messages, id: \.id) { message in
                let index = messageIndexById[message.id] ?? 0
                chatMessageCell(
                    message: message,
                    index: index,
                    lastMsg: lastMsg,
                    todoCardAssistantMessageId: todoCardAssistantMessageId,
                    conversationId: convId
                )
            }
            if shouldShowInlinePlanSummaryInChat,
               coderMode == .agent,
               !hasPersistentPlanCard,
               let cid = conversationId,
               let summary = inlinePlanSummaries[cid]
            {
                PlanSummaryCardView(
                    title: summary.title,
                    summaryMarkdown: summary.body,
                    isCollapsed: isPlanSummaryCollapsed,
                    onToggleCollapse: { isPlanSummaryCollapsed.toggle() },
                    onExpandPlan: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            openPlanPanelForCurrentContext(source: .manualDeepLink)
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .id("plan-summary-card")
            }
            if shouldShowPlanBoardInChat, let board = chatStore.planBoard(for: conversationId) {
                PlanBoardView(
                    board: board,
                    onSelectOption: { selectPlanChoice($0.fullText) }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .id("plan-board")
            }
            // Invisible anchor at the very bottom – scrollTo targets this
            // instead of a message id for stable scroll positioning.
            Color.clear
                .frame(height: 1)
                .id(chatScrollBottomAnchorId)
        }
    }

    @ViewBuilder
    internal func chatMessageCell(
        message: ChatMessage,
        index: Int,
        lastMsg: ChatMessage?,
        todoCardAssistantMessageId: UUID?,
        conversationId: UUID
    ) -> some View {
        let isLast = message.id == lastMsg?.id
        let isLastAssistant = lastMsg?.role == .assistant && isLast
        let userMessageCheckpoint = message.role == .user
            ? chatStore.checkpoint(forMessageIndex: index, conversationId: conversationId)
            : nil
        let hasCheckpointForMessage = userMessageCheckpoint != nil
        let canRewindFromMessage = message.role == .user && !isRewinding
        let needsDivider = message.role == .user && index > 0
        let restoreAction: (() -> Void)? = message.role == .user
            ? { rewindToMessage(at: index, conversationId: conversationId) }
            : nil
        let replyAction: (() -> Void)? = message.role == .assistant
            ? { beginReply(to: message) }
            : nil
        let deleteAction: (() -> Void)? = message.role == .assistant
            ? { chatStore.removeMessage(messageId: message.id, in: conversationId) }
            : nil

        if shouldHideBuildKickoffMessage(message, in: conversationId) {
            EmptyView()
                .id(message.id)
        } else {
            HStack(alignment: .top, spacing: 0) {
                if message.role == .user { Spacer(minLength: 0) }
                if shouldShowPlanAttachmentsInChat,
                   message.role == .assistant,
                   let attachment = message.planAttachment,
                   let entry = planHistoryStore.findEntry(id: attachment.historyEntryId)
                {
                    PlanChatCardView(
                        entry: entry,
                        onDownload: { downloadPlanEntry(entry) },
                        onDuplicate: { _ = planHistoryStore.duplicateEntry(id: entry.id) },
                        onRebuild: {
                            let choice = (entry.chosenPath?.isEmpty == false)
                                ? (entry.chosenPath ?? entry.markdown)
                                : entry.markdown
                            executeWithPlanChoice(
                                choice,
                                fromPlanConversationId: entry.conversationId
                            )
                            planHistoryStore.markRebuilt(id: entry.id)
                        },
                        onOpenInPanel: {
                            planHistoryStore.setSelectedEntry(id: entry.id)
                            openPlanPanelForCurrentContext(
                                preserveHistorySelection: true,
                                source: .manualDeepLink
                            )
                        },
                        onRemove: { planHistoryStore.deleteEntry(id: entry.id) },
                        onExpandPlan: {
                            planHistoryStore.setSelectedEntry(id: entry.id)
                            openPlanPanelForCurrentContext(
                                preserveHistorySelection: true,
                                source: .manualDeepLink
                            )
                        }
                    )
                } else {
                    let suppressPlanArtifacts = shouldSuppressPlanArtifactsInChat(
                        message: message,
                        conversationId: conversationId
                    )
                    let displayMessage = suppressPlanArtifacts
                        ? chatDisplayMessage(from: message, conversationId: conversationId)
                        : message
                    let shouldHideStreamingBarOnPreviousAssistant =
                        message.role == .assistant
                        && !isLastAssistant
                        && lastMsg?.role == .assistant
                        && (lastMsg?.isStreaming ?? false)
                        && isLoadingForCurrentConversation
                    let traceEvents = message.role == .assistant
                        ? toolTraceStore.events(
                            conversationId: conversationId,
                            assistantMessageId: message.id
                        )
                        : []
                    ChatTimelineView(
                        message: displayMessage,
                        context: effectiveContext.context,
                        modeColor: activeModeColor,
                        isActuallyLoading: isLoadingForCurrentConversation,
                        streamingStatusText: shouldHideStreamingBarOnPreviousAssistant ? "" : streamingStatusText(for: displayMessage),
                        streamingDetailText: shouldHideStreamingBarOnPreviousAssistant ? nil : streamingDetailText(for: displayMessage, conversationId: conversationId),
                        traceEvents: traceEvents,
                        todoStore: todoStore,
                        conversationId: conversationId,
                        shouldShowTodo: message.role == .assistant
                            && shouldShowPlanTodosInChat
                            && !todoStore.displayTodosForChat(for: conversationId).isEmpty
                            && message.id == todoCardAssistantMessageId,
                        onFileClicked: { openFilesStore.openFile($0) },
                        onReviewChanges: {
                            gitPanelStore.isOpen = true
                            gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
                        },
                        onRestoreCheckpoint: restoreAction,
                        onReply: replyAction,
                        onDelete: deleteAction,
                        canRewind: canRewindFromMessage,
                        hasCheckpointForRestore: hasCheckpointForMessage,
                        showTopDivider: needsDivider
                    )
                }
                if message.role == .assistant { Spacer(minLength: 0) }
            }
            .id(message.id)
        }
    }
}
