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
        pendingDebugEventsByConversation[eventConversationId, default: []].append(event)
    }

    @MainActor
    internal func applyDebugEventToActiveStore(_ event: NormalizedEvent) {
        switch event {
        case .debugPhaseUpdate(let phase, let detail):
            handleDebugPhaseUpdate(phase: phase, detail: detail)
        case .debugUserRequest(let kind, let prompt):
            handleDebugUserRequest(kind: kind, prompt: prompt)
        case .debugResolved(let summary):
            handleDebugResolved(summary: summary)
        case .debugLog(let payload):
            handleDebugLogPayload(payload)
        case .debugHypothesize(let payload):
            handleDebugHypothesizePayload(payload)
        case .debugMark(let payload):
            handleDebugMarkPayload(payload)
        case .debugInstrument(let payload):
            handleDebugInstrumentPayload(payload)
        case .debugClean(let payload):
            handleDebugCleanPayload(payload)
        case .debugSession(let payload):
            handleDebugSessionPayload(payload)
        case .debugQuery(let payload):
            handleDebugQueryPayload(payload)
        default:
            break
        }
    }

    @MainActor
    internal func persistDebugState(for conversationId: UUID?) {
        guard let conversationId else { return }
        debugStateByConversation[conversationId] = debugStore.snapshot()
    }

    @MainActor
    internal func restoreDebugState(for conversationId: UUID?) {
        guard let conversationId else {
            debugStore.resetSession()
            return
        }
        if let snapshot = debugStateByConversation[conversationId] {
            debugStore.restore(from: snapshot)
        } else {
            debugStore.resetSession()
        }
    }

    @MainActor
    internal func applyPendingDebugEvents(for conversationId: UUID?) {
        guard let conversationId,
              let pending = pendingDebugEventsByConversation.removeValue(forKey: conversationId),
              !pending.isEmpty
        else {
            return
        }
        for event in pending {
            applyDebugEventToActiveStore(event)
        }
        persistDebugState(for: conversationId)
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
            return true
        }
        return eventConversationId == selectedConversationId
    }
}
