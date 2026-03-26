import Foundation

private let kDebugEventBufferLimit = 500

extension PipelineIntegrationService {
    /// `true` quando la proiezione è sospesa (es. Stop dal pannello): gli eventi vanno bufferizzati.
    func isDebugProjectionSuppressed(for conversationId: UUID) -> Bool {
        suppressedDebugProjectionConversationIds.contains(conversationId)
    }

    private static func isHighPriorityDebugEvent(_ event: NormalizedEvent) -> Bool {
        switch event {
        case .debugPhaseUpdate, .activateDebugMode, .debugResolved, .debugClean,
             .debugSession, .debugUserRequest:
            return true
        default:
            return false
        }
    }

    /// Maggiore = eliminare per primo quando il buffer è pieno solo di eventi ad alta priorità.
    private static func criticalDebugControlEventDropScore(_ event: NormalizedEvent) -> Int {
        switch event {
        case .debugResolved, .debugClean:
            return 0
        case .debugPhaseUpdate:
            return 1
        case .debugSession, .debugUserRequest, .activateDebugMode:
            return 2
        default:
            return 3
        }
    }

    func registerDebugStore(
        _ debugStore: DebugStore,
        for conversationId: UUID,
        reactivateProjection: Bool = true,
        applyEffects: @escaping @MainActor (DebugProjectionUIEffects) -> Void = { _ in }
    ) {
        // `reactivateProjection`: su cambio chat (`bindRuntimeDebugProjection`) conserviamo `suspend`
        // finché non arriva `resumeDebugProjection` (es. avvio pipeline debug).
        if reactivateProjection {
            suppressedDebugProjectionConversationIds.remove(conversationId)
        }
        debugStoresByConversation[conversationId] = DebugProjectionStoreBinding(
            store: debugStore,
            applyEffects: applyEffects
        )
        flushPendingDebugEvents(for: conversationId, into: debugStore)
    }

    func unregisterDebugStore(for conversationId: UUID?) {
        guard let conversationId else { return }
        debugStoresByConversation.removeValue(forKey: conversationId)
        // Non azzerare `suppressedDebugProjectionConversationIds`: così uno Stop resta efficace
        // anche dopo cambio conversazione e rientro, finché non c’è `resumeDebugProjection`.
    }

    func suspendDebugProjection(for conversationId: UUID?) {
        guard let conversationId else { return }
        suppressedDebugProjectionConversationIds.insert(conversationId)
    }

    func resumeDebugProjection(for conversationId: UUID?) {
        guard let conversationId else { return }
        suppressedDebugProjectionConversationIds.remove(conversationId)
        guard let binding = debugStoresByConversation[conversationId] else { return }
        if let store = binding.store {
            flushPendingDebugEvents(for: conversationId, into: store)
            return
        }
        let pendingCount = pendingDebugEventsByConversation[conversationId]?.count ?? 0
        debugStoresByConversation.removeValue(forKey: conversationId)
        if pendingCount > 0 {
            NSLog(
                "[PipelineIntegration] resumeDebugProjection: removed zombie binding; %d buffered debug event(s) for conv=%@ await registerDebugStore",
                pendingCount,
                conversationId.uuidString.lowercased()
            )
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
        if let binding = debugStoresByConversation[conversationId] {
            if let store = binding.store {
                let effects = DebugProjectionEventConsumer.apply(event, to: store)
                binding.applyEffects(effects)
                return
            }
            debugStoresByConversation.removeValue(forKey: conversationId)
        }
        bufferDebugEvent(event, for: conversationId)
    }

    private func bufferDebugEvent(_ event: NormalizedEvent, for conversationId: UUID) {
        var pending = pendingDebugEventsByConversation[conversationId, default: []]
        pending.append(event)
        var dropped = 0
        while pending.count > kDebugEventBufferLimit {
            if let idx = pending.firstIndex(where: { !Self.isHighPriorityDebugEvent($0) }) {
                pending.remove(at: idx)
            } else if let dropPair = pending.enumerated().max(by: {
                Self.criticalDebugControlEventDropScore($0.element) < Self.criticalDebugControlEventDropScore($1.element)
            }) {
                pending.remove(at: dropPair.offset)
            } else {
                pending.removeFirst()
            }
            dropped += 1
        }
        if dropped > 0 {
            Self.postBufferDropNotification(conversationId: conversationId, dropped: dropped)
        }
        pendingDebugEventsByConversation[conversationId] = pending
    }

    private static func postBufferDropNotification(conversationId: UUID, dropped: Int) {
        NSLog(
            "[PipelineIntegration] Debug event buffer overflow for conversation %@: dropped %d events (priority trim)",
            conversationId.uuidString,
            dropped
        )
        NotificationCenter.default.post(
            name: .soloCodeDebugEventBufferDropped,
            object: nil,
            userInfo: [
                DebugPipelineBufferNotificationUserInfoKey.conversationId: conversationId,
                DebugPipelineBufferNotificationUserInfoKey.dropped: dropped
            ]
        )
    }

    /// Prima di `unregister`/`suppress` al teardown: scarica la coda verso il `DebugStore` se possibile.
    func resolvePendingDebugEventsBeforeTeardown(for conversationId: UUID) {
        guard let pending = pendingDebugEventsByConversation[conversationId], !pending.isEmpty else {
            pendingDebugEventsByConversation.removeValue(forKey: conversationId)
            return
        }
        let count = pending.count
        let suppressed = suppressedDebugProjectionConversationIds.contains(conversationId)
        if !suppressed,
           let binding = debugStoresByConversation[conversationId],
           let store = binding.store {
            flushPendingDebugEvents(for: conversationId, into: store)
            return
        }
        let hasLiveStore = debugStoresByConversation[conversationId]?.store != nil
        NSLog(
            "[PipelineIntegration] Teardown: dropping %d buffered debug event(s) for conv=%@ suppressed=%@ liveStore=%@",
            count,
            conversationId.uuidString.lowercased(),
            suppressed ? "yes" : "no",
            hasLiveStore ? "yes" : "no"
        )
        pendingDebugEventsByConversation.removeValue(forKey: conversationId)
    }
}
