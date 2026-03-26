import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

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
                    let isActiveStreamingAssistant = isLastAssistant && snapshotIsLoading
                    let shouldHideStreamingBarOnPreviousAssistant =
                        message.role == .assistant
                        && !isLastAssistant
                        && lastMsg?.role == .assistant
                        && (lastMsg?.isStreaming ?? false)
                        && snapshotIsLoading
                    // Use pre-computed trace events from the parent scope.
                    // This avoids accessing toolTraceStore inside the ForEach
                    // body, which would register per-cell SwiftUI dependencies.
                    let traceEvents = precomputedTraceEvents
                    // Only compute streaming status/detail for the active
                    // streaming turn. For all other messages, use stable
                    // empty values to avoid accessing taskActivityStore
                    // (which would cause SwiftUI dependency tracking and
                    // re-render all cells on every activity change).
                    let shouldComputeStreamingText = isActiveStreamingAssistant && !shouldHideStreamingBarOnPreviousAssistant
                    let resolvedStreamingStatusText = shouldComputeStreamingText
                        ? (
                            displayMessage.id == snapshotActiveAssistantMessageId
                                ? snapshotStreamingStatusText
                                : ""
                        ) : ""
                    let resolvedStreamingDetailText: String? = shouldComputeStreamingText
                        ? (
                            displayMessage.id == snapshotActiveAssistantMessageId
                                ? snapshotStreamingDetailText
                                : nil
                        ) : nil
                    // Only the active streaming turn should receive
                    // isActuallyLoading=true. For all others, pass false
                    // to prevent EQ-MISS when the global loading state changes.
                    let cellIsLoading = isActiveStreamingAssistant && snapshotIsLoading
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
                            (isLastAssistant && snapshotIsLoading && displayMessage.id == snapshotActiveAssistantMessageId)
                            ? snapshotInlineActivities : []
                        let liveSupervisorActivities: [TaskActivity] =
                            (isLastAssistant && snapshotIsLoading && displayMessage.id == snapshotActiveAssistantMessageId)
                            ? snapshotSupervisorActivities : []
                        let liveSubagentCards: [SwarmLiveCardState] =
                            (isLastAssistant && snapshotIsLoading && displayMessage.id == snapshotActiveAssistantMessageId)
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
                                    interruptTask()
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
