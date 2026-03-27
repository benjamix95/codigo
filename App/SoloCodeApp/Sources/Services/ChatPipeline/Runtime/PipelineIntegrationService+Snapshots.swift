import Combine
import CoderEngine
import Foundation

extension PipelineIntegrationService {
    func snapshot(for conversationId: UUID?) -> PipelineConversationSnapshot? {
        guard let conversationId else { return nil }
        return snapshotsByConversation[conversationId]
    }

    func snapshotDidChangePublisher(for conversationId: UUID?) -> AnyPublisher<Void, Never> {
        guard let conversationId else {
            return Empty<Void, Never>(completeImmediately: false).eraseToAnyPublisher()
        }
        return snapshotDidChange
            .filter { $0 == conversationId }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func isRunning(for conversationId: UUID?) -> Bool {
        snapshot(for: conversationId)?.isRunning == true
    }

    func runtime(for conversationId: UUID) -> PipelineConversationRuntime? {
        guard let runtime = runtimesByConversation[conversationId],
              runtime.teardownState == .running else {
            return nil
        }
        return runtime
    }

    func providerId(for conversationId: UUID?) -> String? {
        guard let conversationId else { return nil }
        return runtimesByConversation[conversationId]?.providerId
            ?? snapshotsByConversation[conversationId]?.providerId
    }

    func retargetAssistantMessage(
        for conversationId: UUID,
        assistantMessageId: UUID,
        turnId: String
    ) {
        guard let runtime = runtimesByConversation[conversationId] else { return }
        runtime.retargetAssistantMessage(
            assistantMessageId: assistantMessageId,
            turnId: turnId
        )
        flushSnapshotNow(for: conversationId)
    }

    func persistSnapshot(for conversationId: UUID) {
        dirtySnapshotConversationIds.insert(conversationId)
        scheduleSnapshotFlush()
    }

    func flushSnapshotNow(for conversationId: UUID) {
        dirtySnapshotConversationIds.remove(conversationId)
        if let runtime = runtimesByConversation[conversationId] {
            updateSnapshotIfNeeded(runtime.snapshot, for: conversationId)
        } else if snapshotsByConversation[conversationId] != nil {
            snapshotsByConversation.removeValue(forKey: conversationId)
            snapshotDidChange.send(conversationId)
        }
    }

    private func scheduleSnapshotFlush() {
        guard !snapshotFlushScheduled else { return }
        snapshotFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.snapshotFlushScheduled = false
            let dirty = self.dirtySnapshotConversationIds
            self.dirtySnapshotConversationIds.removeAll()
            PipelineSnapshotFlushSignpost.measureBatch(dirtyCount: dirty.count) {
                for conversationId in dirty {
                    if let runtime = self.runtimesByConversation[conversationId] {
                        self.updateSnapshotIfNeeded(runtime.snapshot, for: conversationId)
                    } else if self.snapshotsByConversation[conversationId] != nil {
                        self.snapshotsByConversation.removeValue(forKey: conversationId)
                        self.snapshotDidChange.send(conversationId)
                    }
                }
            }
        }
    }

    @discardableResult
    func updateSnapshotIfNeeded(
        _ snapshot: PipelineConversationSnapshot,
        for conversationId: UUID
    ) -> Bool {
        guard snapshotsByConversation[conversationId] != snapshot else { return false }
        snapshotsByConversation[conversationId] = snapshot
        snapshotDidChange.send(conversationId)
        return true
    }
}
