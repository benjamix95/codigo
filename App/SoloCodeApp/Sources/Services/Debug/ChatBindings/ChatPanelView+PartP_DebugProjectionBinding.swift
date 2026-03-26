import Foundation

extension ChatPanelView {
    @MainActor
    internal func bindRuntimeDebugProjection(for conversationId: UUID?) {
        guard let conversationId else { return }
         pipelineIntegrationService.registerDebugStore(
            debugStore,
            for: conversationId,
            reactivateProjection: false,
            applyEffects: { effects in
                applyDebugProjectionEffects(effects)
            }
        )
        persistDebugState(for: conversationId)
    }

    @MainActor
    internal func suspendRuntimeDebugProjection(for conversationId: UUID?) {
        pipelineIntegrationService.suspendDebugProjection(for: conversationId)
        persistDebugState(for: conversationId)
    }
}
