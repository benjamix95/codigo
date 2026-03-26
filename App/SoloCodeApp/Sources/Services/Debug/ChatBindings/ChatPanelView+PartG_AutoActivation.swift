import Foundation
import CoderEngine

extension ChatPanelView {
    @MainActor
    internal func handleAutoActivatePlanMode(reason: String?) {
        _ = reason
        // Skip if already in plan mode or a plan flow is actively running.
        switch planFlowPhase {
        case .analyzing, .questioning, .generating, .building:
            return
        default:
            break
        }
        planToggleEnabled = true
    }

    @MainActor
    internal func handleAutoActivateDebugMode(reason: String?) {
        let normalizedReason = reason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let workspaceContext = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath,
            scopeMode: ContextScopeMode(rawValue: uiSettings.contextScopeModeRaw) ?? .auto,
            preferDebuggerPromptProfile: true
        )
        let normalizedWorkspacePath = workspaceContext.workspacePath.path
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedWorkspacePath.isEmpty {
            debugStore.debugWorkspacePath = normalizedWorkspacePath
        }
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
        conversationRuntime.pendingTaskActivities.append(activity)
        logTaskBacklogIfNeeded(context: "enqueue_activity")

        let needsImmediateFlush = activity.type == "agent"
            || activity.isRunning
            || TaskActivityStore.isConcreteVisibleEventType(activity.type)
        if needsImmediateFlush {
            conversationRuntime.taskFlushTask?.cancel()
            conversationRuntime.taskFlushTask = nil
            flushPendingTaskActivities()

            // Fast-path: push the sidebar subtitle immediately so it
            // reflects the current tool without waiting for the
            // TaskActivityStore's internal 50ms coalescing buffer.
            if TaskActivityStore.isConcreteVisibleEvent(activity) {
                let label = Self.immediateSubtitleLabel(for: activity)
                if !label.isEmpty,
                   let cid = resolveTaskStatusConversationId(
                    activityPayload: activity.payload,
                    fallbackConversationId: conversationId
                   )
                {
                    chatStore.setTaskStatus(label, for: cid)
                }
            }
        } else {
            scheduleTaskActivityFlush()
        }
    }
}
