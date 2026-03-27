import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    /// Refresh trace events snapshot. Separated from main refresh
    /// so it can be throttled independently.
    internal func refreshTraceEventsSnapshot(fresh: Conversation?) {
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

    internal func refreshLiveActivitySnapshot(fresh: Conversation?) {
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
        let latestAssistantUpdate = scoped.last(where: {
            TaskActivityStore.normalizedEventType($0.type) == "assistant_update"
        })
        let status = TaskActivityStore.streamingStatusText(
            isPaused: executionController.runState == .paused,
            activities: scoped
        )
        let detail = resolvedStreamingDetail(
            activeAssistant: activeAssistant,
            conversationId: convId,
            scopedActivities: scoped,
            activeOperationsCount: scopedActiveOperationsCount(for: convId)
        )

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

        // #region agent log
        if latestAssistantUpdate != nil || snapshotStreamingStatusText == "Thinking" {
            let assistantLogPresent = latestAssistantUpdate != nil
            let assistantLogIsRunning: String = {
                guard let u = latestAssistantUpdate else { return "nil" }
                return "\(u.isRunning)"
            }()
            let assistantLogDetail = String((latestAssistantUpdate?.detail ?? "").prefix(120))
            let assistantLogScope: String = {
                guard let u = latestAssistantUpdate else { return "nil" }
                return canonicalConversationScope(from: u.payload) ?? "nil"
            }()
            let h17Data: [String: String] = [
                "conversationId": convId.uuidString,
                "scopedCount": "\(scoped.count)",
                "assistantUpdatePresent": "\(assistantLogPresent)",
                "assistantUpdateIsRunning": assistantLogIsRunning,
                "assistantUpdateDetail": assistantLogDetail,
                "assistantUpdateConversationScope": assistantLogScope,
                "computedStatus": status,
                "computedDetail": detail ?? "",
            ]
            RuntimeEvidenceDebugLog.appendThrottled(
                gateKey: "H17-live-snapshot-\(convId.uuidString)",
                minInterval: 0.25,
                hypothesisId: "H17",
                location: "refreshLiveActivitySnapshot",
                message: "live_snapshot_inputs",
                data: h17Data
            )
        }
        // #endregion

        if snapshotStreamingStatusText != status || snapshotStreamingDetailText != detail {
            // #region agent log
            RuntimeEvidenceDebugLog.append(
                hypothesisId: "H7",
                location: "refreshLiveActivitySnapshot",
                message: "chat_snapshot_status_updated",
                data: [
                    "conversationId": convId.uuidString,
                    "status": status,
                    "detail": detail ?? "",
                    "previousStatus": snapshotStreamingStatusText,
                    "previousDetail": snapshotStreamingDetailText ?? "",
                    "activitiesCount": "\(scoped.count)",
                ]
            )
            // #endregion
        }
        snapshotActiveAssistantMessageId = activeAssistant.id
        snapshotStreamingStatusText = status
        snapshotStreamingDetailText = detail
        snapshotInlineActivities = inlineActivities
        snapshotSupervisorActivities = supervisorActivities
        snapshotLiveSubagentCards = liveCards
    }
}
