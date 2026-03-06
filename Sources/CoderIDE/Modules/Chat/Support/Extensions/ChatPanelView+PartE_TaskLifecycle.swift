import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func finalChatActionButton(
        icon: String,
        title: String,
        help: String,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
    }

    internal func enableTaskPanelIfNeeded() {
        guard shouldEnableTaskPanelForMode(coderMode) else { return }
        if !taskPanelEnabled {
            taskPanelEnabled = true
        }
    }

    internal func scheduleFallbackTurnStartEvent(conversationId: UUID, providerId: String) {
        fallbackTurnStartWorkItem?.cancel()
        let work = DispatchWorkItem {
            Task { @MainActor in
                guard chatStore.isTaskActive(for: conversationId) else { return }
                guard taskActivityStore.activities.isEmpty else { return }
                recordTaskActivity(
                    type: "turn_started",
                    payload: [
                        "title": "Turn started",
                        "detail": "Request execution in progress",
                        "status": "started",
                        "group_id": "ui-fallback-\(conversationId.uuidString)",
                    ],
                    providerId: providerId,
                    conversationId: conversationId
                )
            }
        }
        fallbackTurnStartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    internal func cancelFallbackTurnStartEvent() {
        fallbackTurnStartWorkItem?.cancel()
        fallbackTurnStartWorkItem = nil
    }

    internal func liveScrollTarget() -> AnyHashable? {
        guard isLoadingForCurrentConversation else { return nil }
        return AnyHashable(chatScrollBottomAnchorId)
    }

    internal var liveTraceEventCount: Int {
        guard let conv = chatStore.conversation(for: conversationId),
              let lastAssistant = conv.messages.last(where: { $0.role == .assistant }) else {
            return 0
        }
        return toolTraceStore.events(
            conversationId: conv.id,
            assistantMessageId: lastAssistant.id
        ).count
    }

    internal var scopedTaskActivityCount: Int {
        scopedTaskActivities(for: conversationId).count
    }

    @ViewBuilder
    internal func subagentCardsSection(message: ChatMessage, isLatestAssistant: Bool) -> some View {
        let liveCards: [SwarmLiveCardState] = (isLatestAssistant && isLoadingForCurrentConversation)
            ? visibleSwarmCardsForChat(from: taskActivityStore.swarmCardStates(for: conversationId))
            : []
        let hasLiveCards = !liveCards.isEmpty

        if hasLiveCards {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(liveCards) { card in
                    SubagentChatCardView(
                        card: card,
                        onOpenInPanel: {
                            selectedSwarmId = card.swarmId
                            showSwarmPanel = true
                        },
                        onStop: {
                            lastTaskEndedByManualStop = true
                            interruptTask()
                        }
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        // Show persisted snapshot cards when live cards aren't available.
        // This avoids a gap where neither live nor snapshot cards are visible.
        if !hasLiveCards, let snapshots = message.subagentCards, !snapshots.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(snapshots) { snapshot in
                    SubagentSnapshotCardView(snapshot: snapshot)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    internal func messageTraceView(
        traceEvents: [ToolTraceEvent],
        effectiveContext: EffectiveContext
    ) -> some View {
        MessageToolTraceView(
            events: traceEvents,
            workspaceHints: traceWorkspaceHints(for: effectiveContext),
            onOpenFile: { openFilesStore.openFile($0) },
            onInteractionStart: {}
        )
    }

    internal func traceWorkspaceHints(for effectiveContext: EffectiveContext) -> [String] {
        let fromContext = effectiveContext.context?.folderPaths
            .filter { !$0.isEmpty } ?? []
        if !fromContext.isEmpty {
            return fromContext
        }
        if let primary = effectiveContext.primaryPath, !primary.isEmpty {
            return [primary]
        }
        return []
    }

    internal func latestMessageScrollTarget() -> AnyHashable? {
        guard chatStore.conversation(for: conversationId)?.messages.last != nil else { return nil }
        return AnyHashable(chatScrollBottomAnchorId)
    }

    internal func scheduleAutoScroll(
        proxy: ScrollViewProxy,
        target: AnyHashable,
        animated: Bool = false,
        delay: TimeInterval = 0.08
    ) {
        let now = Date()
        let sinceLastScroll = now.timeIntervalSince(lastAutoScrollAt)
        if lastAutoScrollTarget == target, sinceLastScroll < 0.10 {
            return
        }
        lastAutoScrollTarget = target
        lastAutoScrollAt = now
        autoScrollWorkItem?.cancel()
        let work = DispatchWorkItem {
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
            if animated {
                withAnimation(.easeOut(duration: 0.14)) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
        autoScrollWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    internal func interruptTask() {
        interruptTask(for: conversationId)
    }

    @MainActor
    internal func launchRunTask(
        for conversationId: UUID,
        operation: @escaping () async -> Void
    ) {
        activeRunTaskByConversation[conversationId]?.cancel()
        let token = UUID()
        activeRunTokenByConversation[conversationId] = token

        let task = Task { @MainActor in
            await operation()
            guard activeRunTokenByConversation[conversationId] == token else { return }
            activeRunTokenByConversation.removeValue(forKey: conversationId)
            activeRunTaskByConversation.removeValue(forKey: conversationId)
        }
        activeRunTaskByConversation[conversationId] = task
    }

    @MainActor
    @discardableResult
    internal func cancelRunTask(for conversationId: UUID?) -> Bool {
        guard let conversationId else { return false }
        guard let task = activeRunTaskByConversation[conversationId] else { return false }
        task.cancel()
        activeRunTaskByConversation.removeValue(forKey: conversationId)
        activeRunTokenByConversation.removeValue(forKey: conversationId)
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
        flushStreamingContent()

        // Flush pending task activities so subagent swarm cards are fully
        // populated before we snapshot them into the assistant message.
        flushPendingTaskActivities()
        taskActivityStore.flushPending()

        // Transition any cards still stuck in .running to .completed
        // so the panel doesn't show stale running indicators.
        taskActivityStore.finalizeRunningSwarmCards(for: targetConversationId)

        let cards = visibleSwarmCardsForChat(from: taskActivityStore.swarmCardStates(for: targetConversationId))
            .map { SubagentCardSnapshot(from: $0) }
        if !cards.isEmpty {
            chatStore.saveSubagentCardsToLastAssistant(cards, in: targetConversationId)
        }
        notifyTaskCompletionIfNeeded(conversationId: targetConversationId, outcome: outcome)
        if shouldEndTask {
            chatStore.endTask(conversationId: targetConversationId)
        }
        // Force immediate persistence so the final state (cards + content)
        // survives an app crash right after task completion.
        chatStore.saveConversationsImmediately()
    }

    internal func visibleSwarmCardsForChat(from cards: [SwarmLiveCardState]) -> [SwarmLiveCardState] {
        return cards
    }
}
