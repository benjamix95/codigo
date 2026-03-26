import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func shouldRecordFallbackTurnStartEvent(
    isTaskActive: Bool,
    scopedActivityCount: Int
) -> Bool {
    isTaskActive && scopedActivityCount == 0
}

func shouldNotifyTaskCompletion(outcome: ToolTraceTurnOutcome?) -> Bool {
    outcome == .success
}

@MainActor
func buildTaskCompletionNotificationPayload(
    conversation: Conversation?,
    outcome: ToolTraceTurnOutcome?,
    formatter: TaskCompletionNotificationFormatter = .default
) -> TaskCompletionNotificationPayload? {
    guard shouldNotifyTaskCompletion(outcome: outcome) else { return nil }
    guard let conversation else { return nil }
    return TaskCompletionNotificationPayload.build(from: conversation, formatter: formatter)
}

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
        uiSettings.taskPanelEnabled = resolveTaskPanelEnabled(
            currentValue: uiSettings.taskPanelEnabled,
            mode: coderMode
        )
    }

    internal func scheduleFallbackTurnStartEvent(conversationId: UUID, providerId: String) {
        conversationRuntime.fallbackTurnStartWorkItemsByConversation[conversationId]?.cancel()
        let work = DispatchWorkItem {
            Task { @MainActor in
                let scopedActivityCount = taskActivityStore.activities(for: conversationId).count
                guard shouldRecordFallbackTurnStartEvent(
                    isTaskActive: chatStore.isTaskActive(for: conversationId),
                    scopedActivityCount: scopedActivityCount
                ) else {
                    conversationRuntime.fallbackTurnStartWorkItemsByConversation.removeValue(forKey: conversationId)
                    return
                }
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
                conversationRuntime.fallbackTurnStartWorkItemsByConversation.removeValue(forKey: conversationId)
            }
        }
        conversationRuntime.fallbackTurnStartWorkItemsByConversation[conversationId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    internal func cancelFallbackTurnStartEvent(for targetConversationId: UUID? = nil) {
        guard let targetConversationId else {
            let pending = conversationRuntime.fallbackTurnStartWorkItemsByConversation.values
            conversationRuntime.fallbackTurnStartWorkItemsByConversation.removeAll()
            for workItem in pending {
                workItem.cancel()
            }
            return
        }
        conversationRuntime.fallbackTurnStartWorkItemsByConversation[targetConversationId]?.cancel()
        conversationRuntime.fallbackTurnStartWorkItemsByConversation.removeValue(forKey: targetConversationId)
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

    @MainActor
    internal func notifyTaskCompletionIfNeeded(
        conversationId: UUID?,
        outcome: ToolTraceTurnOutcome?
    ) {
        guard let conversationId else { return }
        guard let payload = buildTaskCompletionNotificationPayload(
            conversation: chatStore.conversation(for: conversationId),
            outcome: outcome
        ) else {
            return
        }

        Task {
            await TaskCompletionNotificationService.shared.deliver(payload: payload)
        }
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

}
