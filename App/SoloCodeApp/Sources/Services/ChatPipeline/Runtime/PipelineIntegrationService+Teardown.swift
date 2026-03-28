import CoderEngine
import Foundation

extension PipelineIntegrationService {
    func claimTeardownRuntime(for conversationId: UUID) -> PipelineConversationRuntime? {
        guard let runtime = runtimesByConversation[conversationId] else { return nil }
        guard runtime.beginTeardownIfNeeded() else { return nil }
        if let chatStore {
            flushPendingRustBridgeEventsIfNeeded(
                conversationId: conversationId,
                runtime: runtime,
                chatStore: chatStore
            )
        }
        flushSnapshotNow(for: conversationId)
        return runtime
    }

    func completionContext(
        for runtime: PipelineConversationRuntime,
        conversationId: UUID
    ) -> PipelineCompletionContext {
        let durationMs = Int(Date().timeIntervalSince(runtime.jobStartTime) * 1000)
        return PipelineCompletionContext(
            jobId: runtime.currentJobId,
            planConversationId: runtime.planConversationId,
            conversationId: conversationId,
            completedTasks: runtime.completedTasks,
            totalTasks: runtime.totalTasks,
            durationMs: durationMs,
            success: !runtime.wasCancelled && runtime.lastError == nil,
            wasCancelled: runtime.wasCancelled
        )
    }

    func completeTeardown(
        _ runtime: PipelineConversationRuntime,
        for conversationId: UUID,
        completionContext: PipelineCompletionContext?
    ) {
        guard runtime.teardownState != .finished else { return }

        runtime.finishTeardown()
        runtime.rustBridgeDebounceTask?.cancel()
        runtime.rustBridgeDebounceTask = nil
        chatStore?.setLastAssistantStreaming(false, in: conversationId)
        chatStore?.endTask(conversationId: conversationId)
        runtimesByConversation.removeValue(forKey: conversationId)
        snapshotsByConversation.removeValue(forKey: conversationId)
        swarmProgressStore?.clear(conversationId: conversationId)
        resolvePendingDebugEventsBeforeTeardown(for: conversationId)
        unregisterDebugStore(for: conversationId)
        suppressedDebugProjectionConversationIds.remove(conversationId)
        flushSnapshotNow(for: conversationId)
        if let completionContext {
            runtime.onCompletion?(completionContext)
        }
    }
}
