import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @MainActor
    internal func scheduleMessagesSnapshotRefresh(delayNanoseconds: UInt64 = 0) {
        messagesSnapshotRefreshTask?.cancel()
        messagesSnapshotRefreshTask = Task { @MainActor in
            if delayNanoseconds == 0 {
                await Task.yield()
            } else {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            refreshMessagesSnapshot()
        }
    }

    @MainActor
    internal func scheduleLiveActivitySnapshotRefresh(delayNanoseconds: UInt64 = 0) {
        liveActivitySnapshotRefreshTask?.cancel()
        liveActivitySnapshotRefreshTask = Task { @MainActor in
            if delayNanoseconds == 0 {
                await Task.yield()
            } else {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            refreshTaskActivityDependentSnapshots()
        }
    }

    @MainActor
    internal func cancelMessageSnapshotRefreshTasks() {
        messagesSnapshotRefreshTask?.cancel()
        liveActivitySnapshotRefreshTask?.cancel()
    }

    @MainActor
    private func refreshTaskActivityDependentSnapshots() {
        let freshConversation = messagesConversationSnapshot ?? chatStore.conversation(for: conversationId)
        if let convId = conversationId {
            snapshotRootLayoutSwarmCards = taskActivityStore.swarmCardStates(for: convId)
        } else {
            snapshotRootLayoutSwarmCards = []
        }
        refreshLiveActivitySnapshot(fresh: freshConversation)
    }
}
