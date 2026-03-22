import Foundation

extension PipelineIntegrationService {
    func registerDebugStore(
        _ debugStore: DebugStore,
        for conversationId: UUID,
        applyEffects: @escaping @MainActor (DebugProjectionUIEffects) -> Void = { _ in }
    ) {
        debugStoresByConversation[conversationId] = DebugProjectionStoreBinding(
            store: debugStore,
            applyEffects: applyEffects
        )
        flushPendingDebugEvents(for: conversationId, into: debugStore)
    }

    func unregisterDebugStore(for conversationId: UUID?) {
        guard let conversationId else { return }
        debugStoresByConversation.removeValue(forKey: conversationId)
    }

    func suspendDebugProjection(for conversationId: UUID?) {
        guard let conversationId else { return }
        suppressedDebugProjectionConversationIds.insert(conversationId)
        pendingDebugEventsByConversation.removeValue(forKey: conversationId)
    }

    func resumeDebugProjection(for conversationId: UUID?) {
        guard let conversationId else { return }
        suppressedDebugProjectionConversationIds.remove(conversationId)
    }

    func flushPendingDebugEvents(for conversationId: UUID, into debugStore: DebugStore) {
        guard !suppressedDebugProjectionConversationIds.contains(conversationId) else {
            let discardedCount = pendingDebugEventsByConversation[conversationId]?.count ?? 0
            if discardedCount > 0 {
                NSLog("[DebugProjection] Discarding %d buffered debug events for suppressed conversation %@",
                      discardedCount, conversationId.uuidString)
            }
            pendingDebugEventsByConversation.removeValue(forKey: conversationId)
            return
        }
        guard let pending = pendingDebugEventsByConversation.removeValue(forKey: conversationId) else {
            return
        }
        let noopEffects: @MainActor (DebugProjectionUIEffects) -> Void = { _ in }
        let applyEffects = debugStoresByConversation[conversationId]?.applyEffects ?? noopEffects
        for event in pending {
            let effects = DebugProjectionEventConsumer.apply(event, to: debugStore)
            applyEffects(effects)
        }
    }

    func applyOrBufferDebugEvent(_ event: NormalizedEvent, for conversationId: UUID) {
        guard !suppressedDebugProjectionConversationIds.contains(conversationId) else {
            return
        }
        if let binding = debugStoresByConversation[conversationId],
           let store = binding.store {
            let effects = DebugProjectionEventConsumer.apply(event, to: store)
            binding.applyEffects(effects)
            return
        }
        pendingDebugEventsByConversation[conversationId, default: []].append(event)
    }
}
