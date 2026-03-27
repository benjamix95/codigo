import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

struct ChatStreamingFooterResolution: Equatable {
    let shouldComputeText: Bool
    let statusText: String
    let detailText: String?
    let isActuallyLoading: Bool
    let usesSnapshot: Bool
}

func resolveChatStreamingFooterResolution(
    displayMessage: ChatMessage,
    isLastAssistant: Bool,
    lastMessage: ChatMessage?,
    isLoadingForCurrentConversation: Bool,
    snapshotIsLoading: Bool,
    snapshotActiveAssistantMessageId: UUID?,
    snapshotStreamingStatusText: String,
    snapshotStreamingDetailText: String?,
    fallbackStatusText: String,
    fallbackDetailText: String?
) -> ChatStreamingFooterResolution {
    let isActiveStreamingAssistant =
        isLastAssistant && displayMessage.isStreaming && isLoadingForCurrentConversation
    let shouldHideStreamingBarOnPreviousAssistant =
        displayMessage.role == .assistant
        && !isLastAssistant
        && lastMessage?.role == .assistant
        && (lastMessage?.isStreaming ?? false)
        && isLoadingForCurrentConversation
    let shouldComputeStreamingText = isActiveStreamingAssistant && !shouldHideStreamingBarOnPreviousAssistant
    let usesSnapshot =
        shouldComputeStreamingText
        && snapshotIsLoading
        && displayMessage.id == snapshotActiveAssistantMessageId
    let statusText = shouldComputeStreamingText
        ? (usesSnapshot && !snapshotStreamingStatusText.isEmpty ? snapshotStreamingStatusText : fallbackStatusText)
        : ""
    let detailText = shouldComputeStreamingText
        ? (usesSnapshot && snapshotStreamingDetailText != nil ? snapshotStreamingDetailText : fallbackDetailText)
        : nil
    return ChatStreamingFooterResolution(
        shouldComputeText: shouldComputeStreamingText,
        statusText: statusText,
        detailText: detailText,
        isActuallyLoading: isActiveStreamingAssistant,
        usesSnapshot: usesSnapshot
    )
}

extension ChatPanelView {
    @ViewBuilder
    internal func chatMessageCell(
        message: ChatMessage,
        index: Int,
        lastMsg: ChatMessage?,
        todoCardAssistantMessageId: UUID?,
        conversationId: UUID,
        precomputedTraceEvents: [ToolTraceEvent] = []
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
                    let fallbackStreamingStatusText = streamingStatusText(for: displayMessage)
                    let fallbackStreamingDetailText = streamingDetailText(
                        for: displayMessage,
                        conversationId: conversationId
                    )
                    let footerResolution = resolveChatStreamingFooterResolution(
                        displayMessage: displayMessage,
                        isLastAssistant: isLastAssistant,
                        lastMessage: lastMsg,
                        isLoadingForCurrentConversation: isLoadingForCurrentConversation,
                        snapshotIsLoading: snapshotIsLoading,
                        snapshotActiveAssistantMessageId: snapshotActiveAssistantMessageId,
                        snapshotStreamingStatusText: snapshotStreamingStatusText,
                        snapshotStreamingDetailText: snapshotStreamingDetailText,
                        fallbackStatusText: fallbackStreamingStatusText,
                        fallbackDetailText: fallbackStreamingDetailText
                    )
                    let _ = {
                        guard footerResolution.shouldComputeText else { return }
                        ChatLiveDebugNDJSON.appendThrottled(
                            gateKey: "footer:\(conversationId.uuidString.lowercased()):\(displayMessage.id.uuidString.lowercased())",
                            message: "streaming_footer_resolution",
                            data: [
                                "conversationId": conversationId.uuidString.lowercased(),
                                "messageId": displayMessage.id.uuidString.lowercased(),
                                "isLastAssistant": isLastAssistant ? "true" : "false",
                                "messageIsStreaming": displayMessage.isStreaming ? "true" : "false",
                                "isLoadingForConversation": isLoadingForCurrentConversation ? "true" : "false",
                                "snapshotIsLoading": snapshotIsLoading ? "true" : "false",
                                "usesSnapshot": footerResolution.usesSnapshot ? "true" : "false",
                                "statusText": footerResolution.statusText,
                                "detailText": footerResolution.detailText ?? "",
                            ]
                        )
                    }()
                    // Use pre-computed trace events from the parent scope.
                    // This avoids accessing toolTraceStore inside the ForEach
                    // body, which would register per-cell SwiftUI dependencies.
                    let traceEvents = precomputedTraceEvents
                    let resolvedStreamingStatusText = footerResolution.statusText
                    let resolvedStreamingDetailText = footerResolution.detailText
                    let cellIsLoading = footerResolution.isActuallyLoading
                    if displayMessage.role == .user {
                        MessageRow(
                            message: displayMessage,
                            context: effectiveContext.context,
                            modeColor: activeModeColor,
                            isActuallyLoading: cellIsLoading,
                            streamingStatusText: resolvedStreamingStatusText,
                            streamingDetailText: resolvedStreamingDetailText,
                            onFileClicked: { openFilesStore.openFile($0) },
                            onRestoreCheckpoint: restoreAction,
                            onEdit: { editedText in
                                editAndResendMessage(
                                    editedText: editedText,
                                    at: index,
                                    conversationId: conversationId
                                )
                            },
                            onReply: replyAction,
                            onDelete: deleteAction,
                            canRewind: canRewindFromMessage,
                            hasCheckpointForRestore: hasCheckpointForMessage,
                            showTopDivider: needsDivider
                        )
                    } else {
                        let shouldShowTodoCardInTurn =
                            shouldShowPlanTodosInChat
                            && !todoStore.displayTodosForChat(for: conversationId).isEmpty
                            && message.id == todoCardAssistantMessageId
                        let liveInlineActivities: [TaskActivity] =
                            (footerResolution.usesSnapshot)
                            ? snapshotInlineActivities : []
                        let liveSupervisorActivities: [TaskActivity] =
                            (footerResolution.usesSnapshot)
                            ? snapshotSupervisorActivities : []
                        let liveSubagentCards: [SwarmLiveCardState] =
                            (footerResolution.usesSnapshot)
                            ? snapshotLiveSubagentCards : []
                        ChatTurnView(
                            message: displayMessage,
                            context: effectiveContext.context,
                            modeColor: activeModeColor,
                            isActuallyLoading: cellIsLoading,
                            streamingStatusText: resolvedStreamingStatusText,
                            streamingDetailText: resolvedStreamingDetailText,
                            traceEvents: traceEvents,
                            inlineActivities: liveInlineActivities,
                            supervisorActivities: liveSupervisorActivities,
                            liveSubagentCards: liveSubagentCards,
                            todoItems: shouldShowTodoCardInTurn
                                ? todoStore.displayTodosForChat(for: conversationId) : [],
                            conversationId: conversationId,
                            reasoningPolicyProviderId: resolvedTurnProviderId(for: conversationId),
                            shouldShowTodo: shouldShowTodoCardInTurn,
                            canEdit: displayMessage.role == .user,
                            canDelete: deleteAction != nil,
                            onAction: { action in
                                switch action {
                                case .fileClicked(let path):
                                    openFilesStore.openFile(path)
                                case .reviewChanges:
                                    gitPanelStore.isOpen = true
                                    gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
                                case .openSubagentPanel(let swarmId):
                                    selectedSwarmId = swarmId
                                    showSwarmPanel = true
                                case .stopSubagent:
                                    lastTaskEndedByManualStop = true
                                    interruptTask(for: conversationId, source: "chat_turn_stop_subagent")
                                case .reply:
                                    replyAction?()
                                case .edit:
                                    inputText = displayMessage.content
                                    isInputFocused = true
                                case .delete:
                                    deleteAction?()
                                }
                            },
                            onPlanningNextMoveTap: (resolvedStreamingStatusText == "Planning next move" && cellIsLoading)
                                ? { performPlanningNextMoveUserAction() }
                                : nil,
                            showTopDivider: needsDivider,
                            clipboardMarkdownOverride: suppressPlanArtifacts
                                ? message.exportMarkdownContent
                                : nil
                        )
                    }
                }
                if message.role == .assistant { Spacer(minLength: 0) }
            }
            .id(message.id)
        }
    }
}
