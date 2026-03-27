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
    internal func scheduleChromeRuntimeSnapshotRefresh(delayNanoseconds: UInt64 = 0) {
        chromeRuntimeSnapshotRefreshTask?.cancel()
        chromeRuntimeSnapshotRefreshTask = Task { @MainActor in
            if delayNanoseconds == 0 {
                await Task.yield()
            } else {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            refreshChromeRuntimeSnapshot()
        }
    }

    @MainActor
    internal func cancelMessageSnapshotRefreshTasks() {
        messagesSnapshotRefreshTask?.cancel()
        liveActivitySnapshotRefreshTask?.cancel()
        chromeRuntimeSnapshotRefreshTask?.cancel()
    }

    @MainActor
    private func refreshTaskActivityDependentSnapshots() {
        let freshConversation = messagesConversationSnapshot ?? chatStore.conversation(for: conversationId)
        refreshChromeRuntimeSnapshot()
        refreshLiveActivitySnapshot(fresh: freshConversation)
    }

    @MainActor
    internal func refreshChromeRuntimeSnapshot() {
        if let convId = conversationId {
            snapshotRootLayoutSwarmSteps = swarmProgressStore.steps(for: convId)
            snapshotRootLayoutSwarmCards = taskActivityStore.swarmCardStates(for: convId)
            snapshotRootLayoutActivities = taskActivityStore.activities(for: convId)
            snapshotPipelineConversationSnapshot = pipelineIntegrationService.snapshot(for: convId)
        } else {
            snapshotRootLayoutSwarmSteps = []
            snapshotRootLayoutSwarmCards = []
            snapshotRootLayoutActivities = []
            snapshotPipelineConversationSnapshot = nil
        }
    }
}
