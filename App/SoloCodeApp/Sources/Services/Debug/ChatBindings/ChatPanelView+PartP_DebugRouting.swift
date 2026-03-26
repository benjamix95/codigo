import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    /// Un solo percorso: `PipelineIntegrationService` applica o bufferizza sempre.
    /// `persistDebugState` è innescato da `applyEffects` registrato in `bindRuntimeDebugProjection`.
    @MainActor
    internal func routeDebugEvent(
        _ event: NormalizedEvent,
        payload: [String: String],
        eventConversationId: UUID?
    ) {
        guard !SwarmMetadata.isSwarmEvent(payload), let eventConversationId else {
            return
        }
        pipelineIntegrationService.applyOrBufferDebugEvent(event, for: eventConversationId)
    }

    @MainActor
    internal func persistDebugState(for conversationId: UUID?) {
        guard let conversationId else { return }
        conversationRuntime.debugStateByConversation[conversationId] = debugStore.snapshot()
    }

    @MainActor
    internal func restoreDebugState(for conversationId: UUID?) {
        guard let conversationId else {
            debugStore.resetSession()
            return
        }
        if let snapshot = conversationRuntime.debugStateByConversation[conversationId] {
            debugStore.restore(from: snapshot)
        } else {
            debugStore.resetSession()
        }
    }

    @MainActor
    internal func applyDebugProjectionEffects(_ effects: DebugProjectionUIEffects) {
        guard effects.shouldEnableDebugMode || effects.shouldRevealDebugPanel else { return }
        debugToggleEnabled = true
        if effects.shouldRevealDebugPanel {
            showDebugPanel = true
        }
        if effects.shouldEnableDebugMode && coderMode != .debug {
            selectMode(.debug)
        }
    }
}
