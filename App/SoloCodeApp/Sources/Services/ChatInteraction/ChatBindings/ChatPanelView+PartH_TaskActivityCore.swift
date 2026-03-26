import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal static func immediateSubtitleLabel(for activity: TaskActivity) -> String {
        let t = activity.type.lowercased()
        if activity.isRunning {
            if t.contains("read") || t.contains("glob") { return "Reading files" }
            if t.contains("grep") || t.contains("search") { return "Searching codebase" }
            if t.contains("edit") || t.contains("write") || t.contains("file_change") { return "Editing code" }
            if t.contains("bash") || t.contains("command") { return "Running command" }
            if t.contains("mcp") { return userFacingToolName(from: activity.payload) }
            if t.contains("web_search") { return "Searching web" }
            if t.contains("web_fetch") { return "Fetching page" }
            if t.contains("agent") || t.contains("subagent") { return "Running subagent" }
            if t.hasPrefix("debug_") { return "Debugging" }
            if t.contains("todo") || t.contains("plan_step") { return "Planning next move" }
            return "Running"
        }
        return ""
    }

    @MainActor
    internal func scheduleTaskActivityFlush() {
        if conversationRuntime.taskFlushTask != nil { return }
        conversationRuntime.taskFlushTask = Task { @MainActor in
            let delay = UInt64(taskActivityFlushInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { conversationRuntime.taskFlushTask = nil; return }
            conversationRuntime.taskFlushTask = nil
            flushPendingTaskActivities()
        }
    }

    @MainActor
    internal func flushPendingTaskActivities() {
        flushPendingTaskActivities(conversationId: nil)
    }

    @MainActor
    internal func flushPendingTaskActivities(conversationId targetConversationId: UUID?) {
        let backlogBefore = conversationRuntime.pendingTaskActivities.count + conversationRuntime.pendingInstantGreps.count
        guard backlogBefore > 0 else { return }
        logTaskBacklogIfNeeded(context: "flush_start")

        let activities: [TaskActivity]
        let greps: [InstantGrepResult]
        if let targetConversationId {
            activities = conversationRuntime.pendingTaskActivities.filter {
                canonicalConversationScopeValue(
                    $0.payload["conversation_id"] ?? $0.payload["conversationId"]
                ) == targetConversationId.uuidString.lowercased()
            }
            greps = conversationRuntime.pendingInstantGreps.filter { $0.conversationId == targetConversationId }
            conversationRuntime.pendingTaskActivities.removeAll {
                canonicalConversationScopeValue(
                    $0.payload["conversation_id"] ?? $0.payload["conversationId"]
                ) == targetConversationId.uuidString.lowercased()
            }
            conversationRuntime.pendingInstantGreps.removeAll { $0.conversationId == targetConversationId }
        } else {
            activities = conversationRuntime.pendingTaskActivities
            greps = conversationRuntime.pendingInstantGreps
            conversationRuntime.pendingTaskActivities.removeAll(keepingCapacity: true)
            conversationRuntime.pendingInstantGreps.removeAll(keepingCapacity: true)
        }

        for activity in activities {
            if activity.type == "read_batch_started" || activity.type == "read_batch_completed"
                || activity.type == "web_search_started"
                || activity.type == "web_search_completed"
                || activity.type == "web_search_failed"
                || activity.type == "web_fetch_started"
                || activity.type == "web_fetch_completed"
                || activity.type == "web_fetch_failed"
                || activity.type == "command_execution"
                || activity.type == "bash" || activity.type == "mcp_tool_call"
                || activity.type == "skill_invocation"
            {
                if taskActivityStore.shouldPreserveSwarmCriticalEvent(activity) {
                    taskActivityStore.addActivity(activity)
                } else {
                    taskActivityStore.scheduleAppendOrMergeBatchEvent(activity)
                }
            } else {
                taskActivityStore.addActivity(activity)
            }
        }

        for grep in greps {
            taskActivityStore.scheduleAddInstantGrep(grep)
        }

        updateSidebarTaskStatus()

        let backlogAfter = conversationRuntime.pendingTaskActivities.count + conversationRuntime.pendingInstantGreps.count
        if backlogAfter > 0 {
            logTaskBacklogIfNeeded(context: "flush_reschedule")
            scheduleTaskActivityFlush()
        }
    }

    @MainActor
    internal func logTaskBacklogIfNeeded(context: String) {
        let backlog = conversationRuntime.pendingTaskActivities.count + conversationRuntime.pendingInstantGreps.count
        guard backlog >= taskBacklogDiagnosticThreshold else { return }
        NSLog("[StreamDiag] task_backlog_high count=%d context=%@", backlog, context)
    }

    @MainActor
    internal func clearTaskActivityPipeline() {
        conversationRuntime.taskFlushTask?.cancel()
        conversationRuntime.taskFlushTask = nil
        conversationRuntime.pendingTaskActivities.removeAll(keepingCapacity: true)
        conversationRuntime.pendingInstantGreps.removeAll(keepingCapacity: true)
        taskActivityStore.clear(preservingCodeReviewState: true)
    }

    internal func activityWithConversationContext(
        _ activity: TaskActivity,
        conversationId: UUID?
    ) -> TaskActivity {
        guard let conversationId else { return activity }
        let payload = payloadWithConversationScope(
            payload: activity.payload,
            conversationId: conversationId
        )
        return TaskActivity(
            id: activity.id,
            type: activity.type,
            title: activity.title,
            detail: activity.detail,
            payload: payload,
            timestamp: activity.timestamp,
            phase: activity.phase,
            isRunning: activity.isRunning,
            groupId: activity.groupId
        )
    }

    // MARK: - Composer Todo Helpers

    private var composerTodoLatestAssistant: ChatMessage? {
        guard let cid = conversationId else { return nil }
        return chatStore.conversation(for: cid)?
            .messages
            .last(where: { $0.role == .assistant })
    }

    internal var composerTodoFileChanges: [ToolTraceFileChange] {
        guard let cid = conversationId, let msg = composerTodoLatestAssistant else { return [] }
        let events = toolTraceStore.events(conversationId: cid, assistantMessageId: msg.id)
        return ToolTraceFileChangeMapper.collect(from: events)
    }

    internal var composerTodoMicroStatus: String? {
        guard let cid = conversationId,
              let msg = composerTodoLatestAssistant,
              msg.isStreaming else { return nil }
        if snapshotIsLoading,
           msg.id == snapshotActiveAssistantMessageId,
           cid == messagesConversationSnapshot?.id {
            return snapshotStreamingDetailText
        }
        return streamingDetailText(for: msg, conversationId: cid)
    }

    internal var composerTodoIsStreaming: Bool {
        (composerTodoLatestAssistant?.isStreaming ?? false) && isLoadingForCurrentConversation
    }

    internal var composerTodoRetentionStreamingSignal: Bool {
        composerTodoLatestAssistant?.isStreaming ?? false
    }

    internal var composerTodoItems: [TodoItem] {
        resolveComposerTodoItems(
            todoStore: todoStore,
            conversationId: conversationId
        )
    }
}
