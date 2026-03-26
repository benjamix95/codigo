import Foundation

private let kDebugEventBufferLimit = 500

extension PipelineIntegrationService {
    func registerDebugStore(
        _ debugStore: DebugStore,
        for conversationId: UUID,
        applyEffects: @escaping @MainActor (DebugProjectionUIEffects) -> Void = { _ in }
    ) {
        // Nuovo binding al pannello = riattiva la proiezione per questa conversazione e scarica il buffer.
        // Altrimenti, dopo suspend + cambio thread, flushPending resterebbe bloccato fino a resume esplicito.
        suppressedDebugProjectionConversationIds.remove(conversationId)
        debugStoresByConversation[conversationId] = DebugProjectionStoreBinding(
            store: debugStore,
            applyEffects: applyEffects
        )
        flushPendingDebugEvents(for: conversationId, into: debugStore)
    }

    func unregisterDebugStore(for conversationId: UUID?) {
        guard let conversationId else { return }
        debugStoresByConversation.removeValue(forKey: conversationId)
        suppressedDebugProjectionConversationIds.remove(conversationId)
    }

    func suspendDebugProjection(for conversationId: UUID?) {
        guard let conversationId else { return }
        suppressedDebugProjectionConversationIds.insert(conversationId)
    }

    func resumeDebugProjection(for conversationId: UUID?) {
        guard let conversationId else { return }
        suppressedDebugProjectionConversationIds.remove(conversationId)
        if let binding = debugStoresByConversation[conversationId],
           let store = binding.store {
            flushPendingDebugEvents(for: conversationId, into: store)
        }
    }

    func flushPendingDebugEvents(for conversationId: UUID, into debugStore: DebugStore) {
        guard !suppressedDebugProjectionConversationIds.contains(conversationId) else {
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
            bufferDebugEvent(event, for: conversationId)
            return
        }
        if let binding = debugStoresByConversation[conversationId],
           let store = binding.store {
            let effects = DebugProjectionEventConsumer.apply(event, to: store)
            binding.applyEffects(effects)
            return
        }
        bufferDebugEvent(event, for: conversationId)
    }

    private func bufferDebugEvent(_ event: NormalizedEvent, for conversationId: UUID) {
        var pending = pendingDebugEventsByConversation[conversationId, default: []]
        pending.append(event)
        if pending.count > kDebugEventBufferLimit {
            let dropCount = pending.count - kDebugEventBufferLimit
            NSLog(
                "[PipelineIntegration] Debug event buffer overflow for conversation %@: dropping %d events",
                conversationId.uuidString,
                dropCount
            )
            pending.removeFirst(dropCount)
        }
        pendingDebugEventsByConversation[conversationId] = pending
    }
}
