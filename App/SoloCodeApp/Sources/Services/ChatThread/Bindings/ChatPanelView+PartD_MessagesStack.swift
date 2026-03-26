import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func activeStreamingAssistantMessage(in conv: Conversation) -> ChatMessage? {
        guard snapshotIsLoading,
              let activeMessageId = snapshotActiveAssistantMessageId else { return nil }
        return conv.messages.last(where: {
            $0.id == activeMessageId && $0.role == .assistant
        })
    }

    internal func historyMessages(
        from messages: [ChatMessage],
        excluding activeStreamingMessage: ChatMessage?
    ) -> [ChatMessage] {
        guard let activeStreamingMessage else { return messages }
        return messages.filter { $0.id != activeStreamingMessage.id }
    }

    internal func historyBarrierFingerprint(
        conversationId: UUID?,
        messages: [ChatMessage],
        traceEventsByMessageId: [UUID: [ToolTraceEvent]],
        isLoading: Bool
    ) -> ChatMessagesBarrierFingerprint {
        let lastMessage = messages.last
        return .init(
            conversationId: conversationId,
            messageCount: messages.count,
            lastMessageId: lastMessage?.id,
            lastMessageContentLength: lastMessage?.content.count ?? 0,
            lastMessageReasoningLength: lastMessage?.reasoningText?.count ?? 0,
            lastMessageIsStreaming: lastMessage?.isStreaming ?? false,
            lastMessageBlocksCount: lastMessage?.blocks?.count ?? 0,
            lastMessageTraceEventsCount: lastMessage.flatMap { traceEventsByMessageId[$0.id]?.count } ?? 0,
            isLoading: isLoading
        )
    }

    internal func messagesStack(for conv: Conversation) -> some View {
        let convId = conv.id
        let messages = conv.messages
        let activeStreamingMessage = activeStreamingAssistantMessage(in: conv)
        let historyMessages = historyMessages(from: messages, excluding: activeStreamingMessage)
        let lastMsg = messages.last
        let historyLastMsg = historyMessages.last
        let hasPersistentPlanCard = messages.contains { $0.planAttachment != nil }
        let latestVisibleAssistantMessageId = messages.last(where: {
            $0.role == .assistant && !shouldHideBuildKickoffMessage($0, in: convId)
        })?.id
        // Use snapshotTraceEvents (@State) instead of toolTraceStore
        // (ObservableObject) to avoid registering SwiftUI dependencies.
        let latestAssistantMessageIdWithTrace = messages.last(where: { message in
            guard message.role == .assistant else { return false }
            guard !shouldHideBuildKickoffMessage(message, in: convId) else { return false }
            return !(snapshotTraceEvents[message.id]?.isEmpty ?? true)
        })?.id
        let todoCardAssistantMessageId = resolveTodoCardAssistantMessageId(
            messages: messages,
            activeAssistantMessageId: toolRuntime.activeToolTraceTurnsByConversation[convId]?.assistantMessageId,
            latestAssistantMessageIdWithTrace: latestAssistantMessageIdWithTrace,
            pipelineAssistantMessageId: currentAssistantPipelineTarget(for: convId)?.messageId,
            latestVisibleAssistantMessageId: latestVisibleAssistantMessageId
        )
        let messageIndexById: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: messages.enumerated().map { ($0.element.id, $0.offset) }
        )
        // Use snapshotTraceEvents (@State, updated by refreshMessagesSnapshot)
        // instead of reading toolTraceStore here. This avoids registering a
        // SwiftUI dependency on toolTraceStore.objectWillChange, preventing
        // cascade re-renders on every tool trace append.
        let precomputedTraceEvents = snapshotTraceEvents
        let historyFingerprint = historyBarrierFingerprint(
            conversationId: convId,
            messages: historyMessages,
            traceEventsByMessageId: precomputedTraceEvents,
            isLoading: snapshotIsLoading
        )
        return LazyVStack(alignment: .leading, spacing: 28) {
            Color.clear
                .frame(height: 1)
                .id(chatScrollTopAnchorId)
            ChatMessagesBarrierView(fingerprint: historyFingerprint) {
                ForEach(historyMessages, id: \.id) { message in
                    let index = messageIndexById[message.id] ?? 0
                    chatMessageCell(
                        message: message,
                        index: index,
                        lastMsg: historyLastMsg,
                        todoCardAssistantMessageId: todoCardAssistantMessageId,
                        conversationId: convId,
                        precomputedTraceEvents: precomputedTraceEvents[message.id] ?? []
                    )
                }
            }
            if let activeStreamingMessage {
                let index = messageIndexById[activeStreamingMessage.id] ?? 0
                chatMessageCell(
                    message: activeStreamingMessage,
                    index: index,
                    lastMsg: lastMsg,
                    todoCardAssistantMessageId: todoCardAssistantMessageId,
                    conversationId: convId,
                    precomputedTraceEvents: precomputedTraceEvents[activeStreamingMessage.id] ?? []
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

}
