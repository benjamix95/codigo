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
        let latestAssistantMessageId = messages.last(where: { $0.role == .assistant })?.id
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
                    latestAssistantMessageId: latestAssistantMessageId,
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
            // instead of a message id so that LazyVStack doesn't thrash
            // height estimates for off-screen items.
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
        latestAssistantMessageId: UUID?,
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

        if shouldHideBuildKickoffMessage(message) {
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
                    let isLiveReasoningTarget = conversationId == streamingReasoningConversationId
                        && isLastAssistant
                        && message.isStreaming
                    let effectiveReasoning: String? = {
                        if isLiveReasoningTarget {
                            return streamingReasoningText
                        }
                        return message.reasoningText
                    }()
                    let effectiveReasoningBlocks: [ReasoningBlock] = {
                        if isLiveReasoningTarget {
                            return streamingReasoningBlocks
                        }
                        return []
                    }()
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
                    let useSequentialLayout =
                        sequentialStreamingLayoutEnabled
                        && isLiveReasoningTarget
                        && !streamingSegments.isEmpty
                    VStack(alignment: .leading, spacing: 10) {
                        if useSequentialLayout {
                            sequentialSegmentedContent(
                                message: displayMessage,
                                segments: streamingSegments,
                                effectiveContext: effectiveContext,
                                suppressPlanArtifacts: suppressPlanArtifacts,
                                shouldHideStreamingBar: shouldHideStreamingBarOnPreviousAssistant,
                                restoreAction: restoreAction,
                                replyAction: replyAction,
                                deleteAction: deleteAction,
                                canRewindFromMessage: canRewindFromMessage,
                                hasCheckpointForMessage: hasCheckpointForMessage,
                                needsDivider: needsDivider,
                                latestAssistantMessageId: latestAssistantMessageId,
                                conversationId: conversationId
                            )
                        } else {
                            MessageRow(
                                message: displayMessage,
                                context: effectiveContext.context,
                                modeColor: activeModeColor,
                                isActuallyLoading: isLoadingForCurrentConversation,
                                streamingStatusText: streamingStatusText(for: displayMessage),
                                streamingDetailText: streamingDetailText(for: displayMessage, conversationId: conversationId),
                                streamingReasoningText: effectiveReasoning,
                                streamingReasoningBlocks: effectiveReasoningBlocks,
                                showStreamingBar: !shouldHideStreamingBarOnPreviousAssistant,
                                onFileClicked: { openFilesStore.openFile($0) },
                                onRestoreCheckpoint: restoreAction,
                                onReply: replyAction,
                                onDelete: deleteAction,
                                canRewind: canRewindFromMessage,
                                hasCheckpointForRestore: hasCheckpointForMessage,
                                showTopDivider: needsDivider
                            )
                            if message.role == .assistant {
                                if shouldShowPlanTodosInChat,
                                   !todoStore.displayTodosForChat(for: conversationId).isEmpty,
                                   message.id == latestAssistantMessageId
                                {
                                    TodoLiveInlineCard(
                                        store: todoStore,
                                        conversationId: conversationId,
                                        onOpenFile: { openFilesStore.openFile($0) }
                                    )
                                    .padding(.horizontal, 2)
                                }
                                let traceEvents = toolTraceStore.events(
                                    conversationId: conversationId,
                                    assistantMessageId: message.id
                                )
                                if !traceEvents.isEmpty {
                                    messageTraceView(
                                        traceEvents: traceEvents,
                                        effectiveContext: effectiveContext
                                    )
                                }
                            }
                        }
                    }
                }
                if message.role == .assistant { Spacer(minLength: 0) }
            }
            .id(message.id)
        }
    }

    @ViewBuilder
    internal func sequentialSegmentedContent(
        message: ChatMessage,
        segments: [MessageSegment],
        effectiveContext: EffectiveContext,
        suppressPlanArtifacts: Bool,
        shouldHideStreamingBar: Bool,
        restoreAction: (() -> Void)?,
        replyAction: (() -> Void)?,
        deleteAction: (() -> Void)?,
        canRewindFromMessage: Bool,
        hasCheckpointForMessage: Bool,
        needsDivider: Bool,
        latestAssistantMessageId: UUID?,
        conversationId: UUID
    ) -> some View {
        let contentMaxWidth: CGFloat = 800
        let isStreaming = message.isStreaming && isLoadingForCurrentConversation

        if needsDivider {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.0),
                            Color.primary.opacity(0.06),
                            Color.primary.opacity(0.06),
                            Color.primary.opacity(0.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
                .frame(maxWidth: 860)
                .padding(.bottom, 20)
        }

        HStack(spacing: 5) {
            Circle()
                .fill(activeModeColor.opacity(0.6))
                .frame(width: 5.5, height: 5.5)
            Text("Codigo")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.3)
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .padding(.bottom, 5)

        ForEach(segments) { segment in
            switch segment.kind {
            case .reasoning(let text):
                ThinkingBlockView(text: text, isLiveStreaming: isStreaming)
                    .padding(.bottom, 4)
            case .text(let content):
                if !content.isEmpty {
                    MarkdownContentView(
                        content: content,
                        context: effectiveContext.context,
                        onFileClicked: { openFilesStore.openFile($0) },
                        textAlignment: .leading,
                        isStreaming: isStreaming
                    )
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .padding(.vertical, 4)
                }
            case .toolTrace(let events):
                if !events.isEmpty {
                    messageTraceView(
                        traceEvents: events,
                        effectiveContext: effectiveContext
                    )
                }
            }
        }

        if isStreaming, !shouldHideStreamingBar {
            let status = streamingStatusText(for: message).isEmpty ? "Thinking" : streamingStatusText(for: message)
            HStack(spacing: 6) {
                Text(status)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textShimmer(active: true)
                if status != "Planning next move",
                   let detail = streamingDetailText(for: message, conversationId: conversationId),
                   !detail.isEmpty
                {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textShimmer(active: true)
                }
                Spacer()
            }
            .padding(.top, 2)
        }

        if shouldShowPlanTodosInChat,
           !todoStore.displayTodosForChat(for: conversationId).isEmpty,
           message.id == latestAssistantMessageId
        {
            TodoLiveInlineCard(
                store: todoStore,
                conversationId: conversationId,
                onOpenFile: { openFilesStore.openFile($0) }
            )
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    internal var finalChatActionsBar: some View {
        let conv = chatStore.conversation(for: conversationId)
        let messageCount = conv?.messages.count ?? 0
        let assistantCount = conv?.messages.filter { $0.role == .assistant }.count ?? 0
        let userCount = conv?.messages.filter { $0.role == .user }.count ?? 0
        let latestAssistantMessageId = conv?.messages.last(where: { $0.role == .assistant })?.id
        let traceEvents = {
            guard let c = conv, let assistantId = latestAssistantMessageId else { return [ToolTraceEvent]() }
            return toolTraceStore.events(conversationId: c.id, assistantMessageId: assistantId)
        }()
        let editCount = traceEvents.filter { ToolTraceFileChangeMapper.isFileChangeEvent($0) }.count
        let fileChanges = ToolTraceFileChangeMapper.collect(from: traceEvents)
        let linesAdded = fileChanges.reduce(0) { $0 + max(0, $1.added) }
        let linesRemoved = fileChanges.reduce(0) { $0 + max(0, $1.removed) }

        VStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            activeModeColor.opacity(0.0),
                            activeModeColor.opacity(0.12),
                            activeModeColor.opacity(0.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 40)

            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(activeModeColor.opacity(0.8))
                        .frame(width: 6, height: 6)
                    Text("Task completed")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.2)
                }

                if messageCount > 0 {
                    HStack(spacing: 16) {
                        finalStatPill(
                            icon: "bubble.left.and.bubble.right",
                            value: "\(userCount + assistantCount)",
                            label: "messages"
                        )
                        if editCount > 0 {
                            finalStatPill(
                                icon: "pencil",
                                value: "\(editCount)",
                                label: editCount == 1 ? "edit" : "edits"
                            )
                        }
                        if fileChanges.count > 0 {
                            finalStatPill(
                                icon: "doc.text",
                                value: "\(fileChanges.count)",
                                label: fileChanges.count == 1 ? "file" : "files"
                            )
                        }
                        if linesAdded > 0 || linesRemoved > 0 {
                            HStack(spacing: 4) {
                                Text("+\(linesAdded)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(DesignSystem.Colors.success.opacity(0.8))
                                Text("-\(linesRemoved)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(DesignSystem.Colors.error.opacity(0.8))
                            }
                        }
                    }
                }

                HStack(spacing: 6) {
                    finalChatActionButton(
                        icon: didCopyAllChat ? "checkmark" : "doc.on.doc",
                        title: didCopyAllChat ? "Copied" : "Copy all",
                        help: didCopyAllChat ? "Copied" : "Copy entire chat as Markdown",
                        foreground: didCopyAllChat ? DesignSystem.Colors.success : .secondary,
                        action: copyWholeChatToClipboard
                    )
                    finalChatActionButton(
                        icon: "arrow.down.to.line",
                        title: "Export",
                        help: "Download chat as Markdown",
                        foreground: .secondary,
                        action: downloadCurrentConversationMarkdown
                    )
                    finalChatActionButton(
                        icon: "arrow.triangle.branch",
                        title: "Fork",
                        help: "Fork this chat into a new thread",
                        foreground: .secondary,
                        action: forkCurrentConversation
                    )
                }
            }
            .padding(.vertical, 16)
        }
        .frame(maxWidth: chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
    }

    internal func finalStatPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.quaternary)
            Text(value)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.quaternary)
        }
    }

}
