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
        // Wrap in ChatMessagesBarrierView (Equatable) so SwiftUI can
        // skip body re-evaluation when the fingerprint hasn't changed.
        // Without this, parent body invalidations (from 14+ EnvironmentObjects)
        // cascade into messagesStack even when no data changed.
        ChatMessagesBarrierView(
            fingerprint: ChatMessagesBarrierView.Fingerprint(
                conversationId: messagesConversationSnapshot?.id,
                messageCount: messagesConversationSnapshot?.messages.count ?? 0,
                lastMessageId: messagesConversationSnapshot?.messages.last?.id,
                lastMessageContentLength: messagesConversationSnapshot?.messages.last?.content.count ?? 0,
                lastMessageIsStreaming: messagesConversationSnapshot?.messages.last?.isStreaming ?? false,
                lastMessageBlocksCount: messagesConversationSnapshot?.messages.last?.blocks?.count ?? 0,
                isLoading: snapshotIsLoading,
                traceEventsTotalCount: snapshotTraceEvents.values.reduce(0) { $0 + $1.count }
            )
        ) {
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
        let snapshotLastStreaming = messagesConversationSnapshot?.messages.last?.isStreaming ?? false
        let freshLastStreaming = fresh?.messages.last?.isStreaming ?? false
        let snapshotLastBlocks = messagesConversationSnapshot?.messages.last?.blocks?.count ?? -1
        let freshLastBlocks = fresh?.messages.last?.blocks?.count ?? -1

        if messagesConversationSnapshot?.id != fresh?.id
            || snapshotCount != freshCount
            || snapshotLastContent != freshLastContent
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
}
