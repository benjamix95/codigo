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
            }
            .onChange(of: messagesConversationSnapshot?.messages.count) { _ in
                guard isFollowingLive || isLoadingForCurrentConversation else { return }
                handleMessagesCountChange(proxy: proxy)
            }
            .onChange(of: snapshotIsLoading) { newLoading in
                guard !newLoading, isFollowingLive else { return }
                // #region agent log
                AgentDebugSessionNDJSONLog.appendThrottled(
                    gateKey: "H23-snapshot-loading-false",
                    minInterval: 0.35,
                    hypothesisId: "H23",
                    location: "messagesAreaScrollView",
                    message: "scroll_after_snapshot_loading_false",
                    data: [
                        "conversationId": conversationId?.uuidString ?? "nil",
                        "taskLoading": "\(isLoadingForCurrentConversation)",
                    ]
                )
                // #endregion
                scheduleAutoScroll(
                    proxy: proxy,
                    target: chatScrollBottomAnchorId,
                    delay: 0.14,
                    bypassCoalesce: true
                )
            }
            .onChange(of: planningState) { new in
                handlePlanningStateChange(new, proxy: proxy)
            }
            .onChangeCompat(of: chatStore.activeTaskConversationIds) { oldSet, newSet in
                scheduleChromeRuntimeSnapshotRefresh()
                refreshMessagesSnapshot()
                handleActiveTaskConversationChange(oldSet: oldSet, newSet: newSet, proxy: proxy)
            }
            .onReceive(todoStore.objectWillChange) { _ in
                guard isLoadingForCurrentConversation else { return }
                scheduleLiveActivitySnapshotRefresh()
            }
            .onReceive(taskActivityStore.objectWillChange) { _ in
                guard isLoadingForCurrentConversation, conversationId != nil else { return }
                scheduleLiveActivitySnapshotRefresh()
            }
            .onDisappear {
                cancelMessageSnapshotRefreshTasks()
            }
    }
}
