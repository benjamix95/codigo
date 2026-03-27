import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @ViewBuilder
    internal func applyMessagesAreaRefreshModifiers<Content: View>(
        to content: Content,
        proxy: ScrollViewProxy
    ) -> some View {
        content
            .onChange(of: streaming.streamContentVersion) { newVersion in
                let tickStartedAt = Date()
                AgentDebugSessionNDJSONLog.appendThrottled(
                    gateKey: "H10-stream-version",
                    minInterval: 0.08,
                    hypothesisId: "H10",
                    location: "messagesAreaScrollView",
                    message: "stream_content_version_tick",
                    data: [
                        "version": "\(newVersion)",
                        "conversationId": conversationId?.uuidString ?? "nil",
                        "isFollowingLive": "\(isFollowingLive)",
                        "taskLoading": "\(isLoadingForCurrentConversation)",
                    ]
                )
                refreshMessagesSnapshot()
                let refreshMs = Int(Date().timeIntervalSince(tickStartedAt) * 1000)
                guard isFollowingLive || isLoadingForCurrentConversation else { return }
                let scrollStartedAt = Date()
                handleStreamContentVersionChange(proxy: proxy)
                let scrollDispatchMs = Int(Date().timeIntervalSince(scrollStartedAt) * 1000)
                RuntimeEvidenceDebugLog.appendThrottled(
                    gateKey: "H31-stream-version-tick-\(conversationId?.uuidString ?? "nil")",
                    minInterval: 0.10,
                    hypothesisId: "H31",
                    location: "messagesAreaScrollView",
                    message: "stream_content_version_tick_processed",
                    data: [
                        "version": "\(newVersion)",
                        "conversationId": conversationId?.uuidString ?? "nil",
                        "refreshMs": "\(refreshMs)",
                        "scrollDispatchMs": "\(scrollDispatchMs)",
                        "isFollowingLive": "\(isFollowingLive)",
                        "taskLoading": "\(isLoadingForCurrentConversation)",
                    ]
                )
            }
            .onChange(of: messagesConversationSnapshot?.messages.count) { _ in
                guard isFollowingLive || isLoadingForCurrentConversation else { return }
                handleMessagesCountChange(proxy: proxy)
            }
            .onChange(of: planningState) { new in
                handlePlanningStateChange(new, proxy: proxy)
            }
            .onChangeCompat(of: chatStore.activeTaskConversationIds) { oldSet, newSet in
                refreshMessagesSnapshot()
                handleActiveTaskConversationChange(oldSet: oldSet, newSet: newSet, proxy: proxy)
            }
            .onReceive(todoStore.objectWillChange) { _ in
                guard isLoadingForCurrentConversation else { return }
                scheduleLiveActivitySnapshotRefresh()
            }
            .onReceive(taskActivityStore.objectWillChange) { _ in
                guard isLoadingForCurrentConversation, conversationId != nil else { return }
                RuntimeEvidenceDebugLog.appendThrottled(
                    gateKey: "H7-task-activity-store-change-\(conversationId?.uuidString ?? "nil")",
                    minInterval: 0.15,
                    hypothesisId: "H7",
                    location: "messagesArea",
                    message: "task_activity_store_change_without_text_tick",
                    data: [
                        "conversationId": conversationId?.uuidString ?? "nil",
                        "streamContentVersion": "\(streaming.streamContentVersion)",
                        "snapshotStatus": snapshotStreamingStatusText,
                        "snapshotDetail": snapshotStreamingDetailText ?? "",
                    ]
                )
                scheduleLiveActivitySnapshotRefresh()
            }
            .onDisappear {
                cancelMessageSnapshotRefreshTasks()
            }
    }
}
