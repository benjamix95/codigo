import Foundation
import CoderEngine

extension ChatPanelView {
    @MainActor
    internal func handleAutoActivatePlanMode(reason: String?) {
        // Skip if already in plan mode or a plan flow is actively running.
        guard coderMode != .plan else { return }
        switch planFlowPhase {
        case .analyzing, .questioning, .generating, .building:
            return
        default:
            break
        }
        selectMode(.plan)
        planToggleEnabled = true
        if !showPlanPanel {
            openPlanPanelForCurrentContext(
                preserveHistorySelection: false,
                source: .automaticFlow
            )
        }
    }

    @MainActor
    internal func handleAutoActivateDebugMode(reason: String?) {
        let normalizedReason = reason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if coderMode != .debug {
            selectMode(.debug)
        }
        if !showDebugPanel {
            debugToggleEnabled = true
            showDebugPanel = true
        } else {
            debugToggleEnabled = true
        }

        if shouldStartDebugSessionOnAutoActivate(currentPhase: debugStore.phase) {
            debugStore.startDebugSession(errorContext: normalizedReason ?? "")
            return
        }

        guard let normalizedReason, !normalizedReason.isEmpty else { return }
        if debugStore.errorSummary.isEmpty {
            debugStore.errorSummary = normalizedReason
        }
    }

    @MainActor
    internal func enqueueTaskActivity(_ activity: TaskActivity) {
        pendingTaskActivities.append(activity)
        logTaskBacklogIfNeeded(context: "enqueue_activity")

        let needsImmediateFlush = activity.type == "agent"
            || activity.isRunning
            || TaskActivityStore.isConcreteVisibleEventType(activity.type)
        if needsImmediateFlush {
            taskFlushTask?.cancel()
            taskFlushTask = nil
            flushPendingTaskActivities()

            // Fast-path: push the sidebar subtitle immediately so it
            // reflects the current tool without waiting for the
            // TaskActivityStore's internal 50ms coalescing buffer.
            if TaskActivityStore.isConcreteVisibleEvent(activity) {
                let label = Self.immediateSubtitleLabel(for: activity)
                if !label.isEmpty,
                   let cid = conversationIdForStatusUpdate(from: activity)
                {
                    chatStore.setTaskStatus(label, for: cid)
                }
            }
        } else {
            scheduleTaskActivityFlush()
        }
    }

    @MainActor
    private func conversationIdForStatusUpdate(from activity: TaskActivity) -> UUID? {
        if let rawConversationId = activity.payload["conversation_id"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !rawConversationId.isEmpty,
           let parsedConversationId = UUID(uuidString: rawConversationId)
        {
            return parsedConversationId
        }
        return conversationId
    }
}
