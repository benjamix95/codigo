import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal var shouldShowMessagesAreaEmptyState: Bool {
        messagesAreaIsEmpty && !isLoadingForCurrentConversation
    }

    internal var messagesAreaEmptyStateOverlay: some View {
        Text("Ask anything, build anything")
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: -40)
            .allowsHitTesting(false)
    }

    internal var messagesAreaIsEmpty: Bool {
        guard let conv = chatStore.conversation(for: conversationId) else { return true }
        return conv.messages.isEmpty
    }

    internal func handleStreamContentVersionChange(proxy: ScrollViewProxy) {
        guard isFollowingLive else { return }
        scheduleAutoScroll(proxy: proxy, target: chatScrollBottomAnchorId, delay: 0.04)
    }

    internal func handleMessagesCountChange(proxy: ScrollViewProxy) {
        guard isFollowingLive else { return }
        // Use a longer delay than streamContentVersion (0.04s) so that
        // during streaming, the content version handler handles the scroll
        // and this one gets coalesced by scheduleAutoScroll's throttle.
        // Previously both fired within 10ms of each other with animation,
        // causing duplicate layout passes.
        scheduleAutoScroll(proxy: proxy, target: chatScrollBottomAnchorId, delay: 0.12)
    }

    internal func handleLiveTraceEventsChange(proxy: ScrollViewProxy) {
        guard isLoadingForCurrentConversation, isFollowingLive else { return }
        if let target = liveScrollTarget() {
            // Use a slightly longer delay to let streamContentVersion
            // handle the primary scroll; this acts as a fallback.
            scheduleAutoScroll(proxy: proxy, target: target, delay: 0.14)
        }
    }

    internal func handlePlanningStateChange(_ newState: PlanningState, proxy: ScrollViewProxy) {
        if case .awaitingChoice = newState {
            if let target = latestMessageScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0)
            }
        } else if case .awaitingClarification = newState {
            if let target = latestMessageScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0)
            }
        }
    }

    internal func handleActiveTaskConversationChange(
        oldSet: Set<UUID>,
        newSet: Set<UUID>,
        proxy: ScrollViewProxy
    ) {
        guard let cid = conversationId else { return }
        let isActive = newSet.contains(cid)
        let wasActive = oldSet.contains(cid)
        if !wasActive && isActive {
            isFollowingLive = true
            if let target = liveScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, delay: 0)
            }
        } else if wasActive && !isActive {
            cancelFallbackTurnStartEvent()
            isFollowingLive = true
            if let target = latestMessageScrollTarget() {
                // Previously scheduled two overlapping scrolls (0s + 0.16s) with
                // animation. The double schedule raced with other handlers and
                // contributed to main thread saturation. A single delayed scroll
                // is sufficient — the 0.35s throttle in scheduleAutoScroll
                // prevents rapid-fire duplicates.
                scheduleAutoScroll(proxy: proxy, target: target, delay: 0.08)
            }
        }
    }

    internal func handleTaskActivitiesChange(proxy: ScrollViewProxy) {
        guard isLoadingForCurrentConversation, isFollowingLive else { return }
        if let target = liveScrollTarget() ?? latestMessageScrollTarget() {
            scheduleAutoScroll(proxy: proxy, target: target, delay: 0.08)
        }
    }

    @ViewBuilder
    internal var chatMessagesAreaContent: some View {
        if let conv = messagesConversationSnapshot {
            messagesStack(for: conv)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: 1)
                    .id(chatScrollTopAnchorId)
                Color.clear
                    .frame(height: 1)
                    .id(chatScrollBottomAnchorId)
            }
        }
    }

    /// Refresh conversation and loading snapshot from ObservableObjects.
    /// Called on every streamContentVersion change and messages.count change.
    internal func refreshMessagesSnapshot() {
        let fresh = chatStore.conversation(for: conversationId)

        // Always update loading state.
        let freshLoading = chatStore.isTaskActive(for: conversationId)
            || pipelineIntegrationService.isRunning(for: conversationId)
        if snapshotIsLoading != freshLoading {
            snapshotIsLoading = freshLoading
        }

        // Only update conversation if actually different.
        let snapshotCount = messagesConversationSnapshot?.messages.count ?? -1
        let freshCount = fresh?.messages.count ?? -1
        let snapshotLastContent = messagesConversationSnapshot?.messages.last?.content.count ?? -1
        let freshLastContent = fresh?.messages.last?.content.count ?? -1
        let snapshotLastReasoning = messagesConversationSnapshot?.messages.last?.reasoningText?.count ?? -1
        let freshLastReasoning = fresh?.messages.last?.reasoningText?.count ?? -1
        let snapshotLastStreaming = messagesConversationSnapshot?.messages.last?.isStreaming ?? false
        let freshLastStreaming = fresh?.messages.last?.isStreaming ?? false
        let snapshotLastBlocks = messagesConversationSnapshot?.messages.last?.blocks?.count ?? -1
        let freshLastBlocks = fresh?.messages.last?.blocks?.count ?? -1

        if messagesConversationSnapshot?.id != fresh?.id
            || snapshotCount != freshCount
            || snapshotLastContent != freshLastContent
            || snapshotLastReasoning != freshLastReasoning
            || snapshotLastStreaming != freshLastStreaming
            || snapshotLastBlocks != freshLastBlocks
        {
            messagesConversationSnapshot = fresh
        }

        // Throttle trace events refresh: only update at most every 250ms.
        // This prevents the barrier fingerprint from changing on every
        // streamContentVersion increment (215+ per session), which was
        // causing ~710 EQ-MISS. Text deltas are the most frequent
        // streamContentVersion source but don't affect trace events.
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastTraceRefreshTime
        if elapsed >= 0.25 || !snapshotIsLoading {
            refreshTraceEventsSnapshot(fresh: fresh)
            lastTraceRefreshTime = now
        }

        let activityElapsed = now - lastActivityRefreshTime
        if activityElapsed >= 0.25 || !snapshotIsLoading {
            refreshLiveActivitySnapshot(fresh: fresh)
            lastActivityRefreshTime = now
        }
    }

    /// Refresh trace events snapshot. Separated from main refresh
    /// so it can be throttled independently.
    private func refreshTraceEventsSnapshot(fresh: Conversation?) {
        guard let convId = conversationId ?? fresh?.id else { return }
        var newTraceMap: [UUID: [ToolTraceEvent]] = [:]
        for msg in (fresh?.messages ?? []) where msg.role == .assistant {
            newTraceMap[msg.id] = toolTraceStore.events(
                conversationId: convId,
                assistantMessageId: msg.id
            )
        }
        let countsChanged = newTraceMap.contains { key, events in
            snapshotTraceEvents[key]?.count != events.count
        } || newTraceMap.count != snapshotTraceEvents.count
        if countsChanged {
            snapshotTraceEvents = newTraceMap
        }
    }

    private func refreshLiveActivitySnapshot(fresh: Conversation?) {
        guard snapshotIsLoading, let convId = conversationId ?? fresh?.id else {
            snapshotActiveAssistantMessageId = nil
            snapshotStreamingStatusText = ""
            snapshotStreamingDetailText = nil
            snapshotInlineActivities = []
            snapshotSupervisorActivities = []
            snapshotLiveSubagentCards = []
            return
        }

        guard let activeAssistant = fresh?.messages.last(where: { $0.role == .assistant }) else {
            snapshotActiveAssistantMessageId = nil
            snapshotStreamingStatusText = ""
            snapshotStreamingDetailText = nil
            snapshotInlineActivities = []
            snapshotSupervisorActivities = []
            snapshotLiveSubagentCards = []
            return
        }

        let scoped = scopedTaskActivities(for: convId)
        let status = TaskActivityStore.streamingStatusText(
            isPaused: executionController.runState == .paused,
            activities: scoped
        )
        let detail: String? = {
            if let assistantUpdate = TaskActivityStore.assistantUpdateText(in: scoped) {
                return assistantUpdate
            }
            if let fromActivities = TaskActivityStore.streamingDetailText(
                activities: scoped,
                activeOperationsCount: scopedActiveOperationsCount(for: convId)
            ) {
                return fromActivities
            }
            if let fromContent = ChatStore.extractLastOperationalThinkingLine(from: activeAssistant.content) {
                return fromContent
            }
            if let codexLine = streaming.codexLastReasoningLine, !codexLine.isEmpty, convId == self.conversationId {
                return codexLine.count > 80 ? String(codexLine.prefix(77)) + "..." : codexLine
            }
            if convId == streaming.streamingReasoningConversationId,
               let reasoning = streaming.streamingReasoningText,
               !reasoning.isEmpty {
                let lastLine = reasoning.split(separator: "\n", omittingEmptySubsequences: false)
                    .last?
                    .trimmingCharacters(in: CharacterSet.whitespaces) ?? ""
                if !lastLine.isEmpty {
                    return lastLine.count > 80 ? String(lastLine.prefix(77)) + "…" : lastLine
                }
            }
            return nil
        }()

        let inlineActivities = scoped.filter { activity in
            guard TaskActivityStore.isConcreteVisibleEvent(activity) else { return false }
            if SwarmMetadata.isSupervisorEvent(activity.payload) { return false }
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
            return shouldShowOperationEventInLinearChat(
                eventType: activity.type,
                payload: activity.payload,
                showTodoCard: false
            )
        }

        let supervisorActivities = scoped.filter { activity in
            guard TaskActivityStore.isConcreteVisibleEvent(activity) else { return false }
            guard SwarmMetadata.isSupervisorEvent(activity.payload) else { return false }
            if activity.type == "todo_write" || activity.type == "todo_read" {
                return false
            }
            return true
        }

        let liveCards = visibleSwarmCardsForChat(
            from: taskActivityStore.swarmCardStates(for: convId)
        )

        snapshotActiveAssistantMessageId = activeAssistant.id
        snapshotStreamingStatusText = status
        snapshotStreamingDetailText = detail
        snapshotInlineActivities = inlineActivities
        snapshotSupervisorActivities = supervisorActivities
        snapshotLiveSubagentCards = liveCards
    }
}
