import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @MainActor
    internal func routeDebugEvent(
        _ event: NormalizedEvent,
        payload: [String: String],
        eventConversationId: UUID?
    ) {
        if shouldHandleDebugStoreEvent(payload: payload, eventConversationId: eventConversationId) {
            applyDebugEventToActiveStore(event)
            persistDebugState(for: selectedConversationId)
            return
        }
        guard !SwarmMetadata.isSwarmEvent(payload), let eventConversationId else {
            return
        }
        pipelineIntegrationService.applyOrBufferDebugEvent(event, for: eventConversationId)
    }

    @MainActor
    internal func applyDebugEventToActiveStore(_ event: NormalizedEvent) {
        let effects = DebugProjectionEventConsumer.apply(event, to: debugStore)
        applyDebugProjectionEffects(effects)
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
    internal func shouldHandleDebugStoreEvent(payload: [String: String], eventConversationId: UUID?) -> Bool {
        if SwarmMetadata.isSwarmEvent(payload) {
            return false
        }
        guard let selectedConversationId else {
            return false
        }
        guard let eventConversationId else {
            NSLog("[DebugRouting] Discarding unscoped debug event (nil conversationId)")
            return false
        }
        return eventConversationId == selectedConversationId
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
