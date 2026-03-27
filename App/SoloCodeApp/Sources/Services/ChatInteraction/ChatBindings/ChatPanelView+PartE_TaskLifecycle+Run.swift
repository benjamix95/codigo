import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    /// Minimum interval between consecutive auto-scroll operations.
    /// Previously 0.20s which was too low — multiple onChange handlers
    /// (streamContentVersion, messagesCount, planningState, etc.) all
    /// call this within milliseconds of each other, saturating the main
    /// thread with overlapping scrollTo + layout passes. 0.35s is enough
    /// to coalesce bursts while still feeling responsive.
    private static let autoScrollMinInterval: TimeInterval = 0.35

    internal func scheduleAutoScroll(
        proxy: ScrollViewProxy,
        target: AnyHashable,
        animated: Bool = false,
        delay: TimeInterval = 0.08
    ) {
        let now = Date()
        let sinceLastScroll = now.timeIntervalSince(scrollState.lastAutoScrollAt)
        if scrollState.lastAutoScrollTarget == target, sinceLastScroll < Self.autoScrollMinInterval {
            return
        }
        scrollState.lastAutoScrollTarget = target
        scrollState.lastAutoScrollAt = now
        scrollState.autoScrollWorkItem?.cancel()
        let work = DispatchWorkItem { [showsSwarmViewOnly, chatStore, conversationId, chatScrollTopAnchorId, chatScrollBottomAnchorId] in
            guard NSApplication.shared.isActive else { return }
            guard !showsSwarmViewOnly else { return }
            let hasActiveConversation = chatStore.conversation(for: conversationId) != nil
            let availableMessageIDs = Set(
                chatStore.conversation(for: conversationId)?.messages.map(\.id) ?? []
            )
            guard canScrollToTarget(
                target,
                topAnchorId: chatScrollTopAnchorId,
                bottomAnchorId: chatScrollBottomAnchorId,
                allowAnchorTargets: hasActiveConversation,
                availableMessageIDs: availableMessageIDs
            ) else { return }
            // Never use withAnimation for auto-scroll during streaming.
            // Animated scrollTo blocks the main thread layout pass and
            // causes the UI to disappear (black screen) when multiple
            // scroll operations overlap.
            proxy.scrollTo(target, anchor: .bottom)
        }
        scrollState.autoScrollWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    internal func interruptTask() {
        interruptTask(for: conversationId, source: "generic")
    }

    @MainActor
    internal func launchRunTask(
        for conversationId: UUID,
        operation: @escaping () async -> Void
    ) {
        toolRuntime.activeRunTaskByConversation[conversationId]?.cancel()
        let token = UUID()
        toolRuntime.activeRunTokenByConversation[conversationId] = token

        let task = Task { @MainActor in
            await operation()
            guard toolRuntime.activeRunTokenByConversation[conversationId] == token else { return }
            toolRuntime.activeRunTokenByConversation.removeValue(forKey: conversationId)
            toolRuntime.activeRunTaskByConversation.removeValue(forKey: conversationId)
        }
        toolRuntime.activeRunTaskByConversation[conversationId] = task
    }

    @MainActor
    @discardableResult
    internal func cancelRunTask(for conversationId: UUID?) -> Bool {
        guard let conversationId else { return false }
        guard let task = toolRuntime.activeRunTaskByConversation[conversationId] else { return false }
        task.cancel()
        toolRuntime.activeRunTaskByConversation.removeValue(forKey: conversationId)
        toolRuntime.activeRunTokenByConversation.removeValue(forKey: conversationId)
        return true
    }

    @MainActor
    internal func applyFlowCoordinatorState(
        for targetConversationId: UUID?,
        _ transition: (ConversationFlowCoordinator) -> Void
    ) {
        guard targetConversationId == conversationId else { return }
        transition(flowCoordinator)
    }

    /// Snapshots current swarm cards into the last assistant message, then ends the task.
    /// Flushes pending streaming content first to ensure no data is lost.
    @MainActor
    internal func snapshotSubagentCardsAndEndTask(
        conversationId targetConversationId: UUID?,
        outcome: ToolTraceTurnOutcome? = nil,
        shouldEndTask: Bool = true
    ) {
        // Flush any pending streamed content so the assistant message is up-to-date
        // before we attach subagent cards or end the task.
        flushStreamingContent(conversationId: targetConversationId)

        // Flush pending task activities so subagent swarm cards are fully
        // populated before we snapshot them into the assistant message.
        flushPendingTaskActivities(conversationId: targetConversationId)
        let cards = visibleSwarmCardsForChat(
            from: taskActivityStore.finalizedSwarmCardSnapshotForTaskCompletion(
                for: targetConversationId
            )
        )
            .map { SubagentCardSnapshot(from: $0) }
        if !cards.isEmpty {
            chatStore.saveSubagentCardsToLastAssistant(cards, in: targetConversationId)
        }
        notifyTaskCompletionIfNeeded(conversationId: targetConversationId, outcome: outcome)
        if shouldEndTask {
            chatStore.endTask(conversationId: targetConversationId)
        }
        cancelFallbackTurnStartEvent(for: targetConversationId)
        // Force immediate persistence so the final state (cards + content)
        // survives an app crash right after task completion.
        chatStore.saveConversationsImmediately()
    }

    internal func visibleSwarmCardsForChat(from cards: [SwarmLiveCardState]) -> [SwarmLiveCardState] {
        cards.filter { $0.swarmId.lowercased() != "orchestrator" }
    }
}
