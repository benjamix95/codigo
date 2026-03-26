import Foundation
import CoderEngine

extension ChatStore {
    /// Annulla il batch Rust pendente senza applicarlo (es. prima di un sync `persistImmediately: true`).
    @MainActor
    func cancelAssistantContentRustSyncSchedule() {
        assistantContentRustSyncDebounceItem?.cancel()
        assistantContentRustSyncDebounceItem = nil
        pendingAssistantRustSync = nil
    }

    /// Esegue subito l’ultimo `sync_assistant_content` accodato (fine streaming / flush).
    @MainActor
    func flushPendingAssistantContentRustSync() {
        guard let pending = pendingAssistantRustSync else {
            assistantContentRustSyncDebounceItem?.cancel()
            assistantContentRustSyncDebounceItem = nil
            return
        }
        assistantContentRustSyncDebounceItem?.cancel()
        assistantContentRustSyncDebounceItem = nil
        pendingAssistantRustSync = nil
        performDebouncedAssistantContentRustSync(
            conversationId: pending.conversationId,
            messageId: pending.messageId,
            content: pending.content
        )
    }

    @MainActor
    func scheduleAssistantContentRustSync(
        conversationId: UUID,
        messageId: UUID?,
        content: String,
        debounceSeconds: TimeInterval = 0.12
    ) {
        pendingAssistantRustSync = (conversationId, messageId, content)
        assistantContentRustSyncDebounceItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flushPendingAssistantContentRustSync() }
        }
        assistantContentRustSyncDebounceItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceSeconds, execute: work)
    }

    @MainActor
    private func performDebouncedAssistantContentRustSync(
        conversationId: UUID,
        messageId: UUID?,
        content: String
    ) {
        let applied: Bool
        if let messageId {
            applied = applyRustStoreAction("sync_assistant_content") { request in
                request.conversationId = conversationId.uuidString.lowercased()
                request.messageId = messageId.uuidString.lowercased()
                request.text = content
            }
        } else {
            applied = applyRustStoreAction("sync_assistant_content") { request in
                request.conversationId = conversationId.uuidString.lowercased()
                request.text = content
            }
        }
        if !applied {
            fallbackUpdateAssistantContent(
                conversationId: conversationId,
                messageId: messageId,
                content: content
            )
        }
    }
}
