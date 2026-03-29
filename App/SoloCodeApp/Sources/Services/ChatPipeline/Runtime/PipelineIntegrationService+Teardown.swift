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
            // Commit finale esplicito: il percorso Rust-success in
            // `runPipelineEventsCommit` aggiorna lo store via
            // `applyScopedForPipeline` ma NON chiama
            // `ChatPipelineCommitter.commit()`. Senza questo commit
            // il messaggio assistente nello store potrebbe avere
            // blocchi/testo incompleti quando il runtime viene rimosso
            // e la streaming overlay sparisce.
            ChatPipelineCommitter.commit(
                runtime.chatTurnState,
                chatStore: chatStore,
                persistImmediately: true
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
        // Dopo la rimozione di runtime/snapshot, il prossimo refresh SwiftUI
        // leggerà direttamente dallo store base (niente più streaming overlay).
        // Forziamo una notifica non-throttled per garantire che il body venga
        // rivalutato con `snapshotIsLoading = false` e i messaggi storici
        // includano il contenuto assistente appena committato.
        chatStore?.flushConversationChangeNotification()
        if let completionContext {
            runtime.onCompletion?(completionContext)
        }
    }
}
