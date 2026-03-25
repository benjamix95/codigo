import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func messagesStack(for conv: Conversation) -> some View {
        let convId = conv.id
        let messages = conv.messages
        let _ = ChatRenderLogger.logRender(
            "messagesStack",
            detail: "convId=\(convId.uuidString.prefix(8)) msgCount=\(messages.count)"
        )
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
            activeAssistantMessageId: toolRuntime.activeToolTraceTurnsByConversation[convId]?.assistantMessageId,
            latestAssistantMessageIdWithTrace: latestAssistantMessageIdWithTrace,
            pipelineAssistantMessageId: nil,
            latestVisibleAssistantMessageId: latestVisibleAssistantMessageId
        )
        let messageIndexById: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: messages.enumerated().map { ($0.element.id, $0.offset) }
        )
        // Pre-compute trace events for all assistant messages ONCE here,
        // outside the ForEach. This prevents each chatMessageCell from
        // independently accessing toolTraceStore.events() which would
        // register N separate SwiftUI dependencies on the same
        // ObservableObject, causing all N cells to re-evaluate on every
        // single tool trace append.
        let precomputedTraceEvents: [UUID: [ToolTraceEvent]] = {
            var map: [UUID: [ToolTraceEvent]] = [:]
            for msg in messages where msg.role == .assistant {
                map[msg.id] = toolTraceStore.events(
                    conversationId: convId,
                    assistantMessageId: msg.id
                )
            }
            return map
        }()
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
                    conversationId: convId,
                    precomputedTraceEvents: precomputedTraceEvents[message.id] ?? []
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

        let _ = ChatRenderLogger.logRender(
            "chatMessageCell",
            detail: "msgId=\(message.id.uuidString.prefix(8)) role=\(message.role.rawValue) idx=\(index) streaming=\(message.isStreaming)"
        )
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
                    let isActiveStreamingAssistant = isLastAssistant && isLoadingForCurrentConversation
                    let shouldHideStreamingBarOnPreviousAssistant =
                        message.role == .assistant
                        && !isLastAssistant
                        && lastMsg?.role == .assistant
                        && (lastMsg?.isStreaming ?? false)
                        && isLoadingForCurrentConversation
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
                        ? streamingStatusText(for: displayMessage) : ""
                    let resolvedStreamingDetailText: String? = shouldComputeStreamingText
                        ? streamingDetailText(for: displayMessage, conversationId: conversationId) : nil
                    // Only the active streaming turn should receive
                    // isActuallyLoading=true. For all others, pass false
                    // to prevent EQ-MISS when the global loading state changes.
                    let cellIsLoading = isActiveStreamingAssistant && isLoadingForCurrentConversation
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
                            false
                            && shouldShowPlanTodosInChat
                            && !todoStore.displayTodosForChat(for: conversationId).isEmpty
                            && message.id == todoCardAssistantMessageId
                        let liveInlineActivities: [TaskActivity] = {
                            guard isLastAssistant, isLoadingForCurrentConversation else { return [] }
                            return scopedTaskActivities(for: conversationId).filter { activity in
                                guard TaskActivityStore.isConcreteVisibleEvent(activity) else { return false }
                                if SwarmMetadata.isSupervisorEvent(activity.payload) {
                                    return false
                                }
                                if SwarmMetadata.isSwarmEvent(activity.payload)
                                    || activity.type == "agent"
                                    || activity.type == "subagent_text"
                                    || activity.type == "subagent_batch_done"
                                {
                                    return false
                                }
                                if activity.type == "todo_write" || activity.type == "todo_read" {
                                    return false
                                }
                                guard shouldShowOperationEventInLinearChat(
                                    eventType: activity.type,
                                    payload: activity.payload,
                                    showTodoCard: shouldShowTodoCardInTurn
                                ) else {
                                    return false
                                }
                                return true
                            }
                        }()
                        let liveSupervisorActivities: [TaskActivity] = {
                            guard isLastAssistant, isLoadingForCurrentConversation else { return [] }
                            let scoped = scopedTaskActivities(for: conversationId)
                            let hasWorkerCards = !taskActivityStore.swarmCardStates(for: conversationId).isEmpty
                            guard hasWorkerCards else { return [] }
                            return scoped.filter { activity in
                                guard TaskActivityStore.isConcreteVisibleEvent(activity) else { return false }
                                guard SwarmMetadata.isSupervisorEvent(activity.payload) else { return false }
                                if activity.type == "todo_write" || activity.type == "todo_read" {
                                    return false
                                }
                                return true
                            }
                        }()
                        let liveSubagentCards: [SwarmLiveCardState] = {
                            guard isLastAssistant, isLoadingForCurrentConversation else { return [] }
                            return visibleSwarmCardsForChat(
                                from: taskActivityStore.swarmCardStates(for: conversationId)
                            )
                        }()
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
                            showTopDivider: needsDivider
                        )
                    }
                }
                if message.role == .assistant { Spacer(minLength: 0) }
            }
            .id(message.id)
        }
    }
}
