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


        if snapshotStreamingStatusText != status || snapshotStreamingDetailText != detail {
        }
        snapshotActiveAssistantMessageId = activeAssistant.id
        snapshotStreamingStatusText = status
        snapshotStreamingDetailText = detail
        snapshotInlineActivities = inlineActivities
        snapshotSupervisorActivities = supervisorActivities
        snapshotLiveSubagentCards = liveCards
    }
}
