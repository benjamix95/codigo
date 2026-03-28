import CoderEngine
import Foundation

func shouldPreferConversationRuntimeTurnState(
    baseTurnState: ChatTurnState?,
    conversationTurnState: ChatTurnState?,
    conversationId: UUID?
) -> Bool {
    guard let conversationId,
          let conversationTurnState,
          conversationTurnState.conversationId == conversationId
    else { return false }
    guard let baseTurnState else { return true }
    guard baseTurnState.conversationId == conversationId else { return true }

    let baseMarkers = baseTurnState.blocks.filter { $0.kind == .toolMarker }.count
    let conversationMarkers = conversationTurnState.blocks.filter { $0.kind == .toolMarker }.count
    if conversationMarkers > baseMarkers { return true }

    if conversationTurnState.textSegments.count > baseTurnState.textSegments.count {
        return true
    }

    if conversationTurnState.timelineSegments.count > baseTurnState.timelineSegments.count {
        return true
    }

    return conversationTurnState.timelineNextSequence > baseTurnState.timelineNextSequence
}

func preferredConversationRuntimeSnapshot(
    baseSnapshot: MainChatRuntimeSnapshotBridge?,
    conversationTurnState: ChatTurnState?,
    conversationId: UUID?
) -> MainChatRuntimeSnapshotBridge? {
    let baseTurnState = baseSnapshot.map(\.turnState.chatTurnState)
    guard shouldPreferConversationRuntimeTurnState(
        baseTurnState: baseTurnState,
        conversationTurnState: conversationTurnState,
        conversationId: conversationId
    ) else {
        return baseSnapshot
    }
    guard let conversationTurnState else { return baseSnapshot }
    if var baseSnapshot {
        baseSnapshot.turnState = MainChatBridgeState(conversationTurnState)
        return baseSnapshot
    }
    return MainChatRuntimeSnapshotBridge(
        turnState: MainChatBridgeState(conversationTurnState),
        mode: .agent,
        directStream: nil,
        plan: nil,
        output: nil
    )
}

extension ChatPanelView {
    @MainActor
    internal func resolvedMainChatRuntimeSnapshot(
        preferPlanRuntime: Bool = false
    ) -> MainChatRuntimeSnapshotBridge? {
        if preferPlanRuntime {
            return flowCoordinator.planRuntimeSnapshotState()
                ?? flowCoordinator.directRuntimeSnapshotState()
        }
        return flowCoordinator.directRuntimeSnapshotState()
            ?? flowCoordinator.planRuntimeSnapshotState()
    }

    @MainActor
    internal func runtimeSnapshotForPlanUIIntent(
        targetConversationId: UUID?
    ) -> MainChatRuntimeSnapshotBridge? {
        let target = targetConversationId ?? conversationId
        guard let target else {
            return resolvedMainChatRuntimeSnapshot(preferPlanRuntime: true)
        }
        guard let current = conversationId, target == current else { return nil }
        return resolvedMainChatRuntimeSnapshot(preferPlanRuntime: true)
    }

    @MainActor
    internal func preferredMainChatRuntimeSnapshot(
        baseSnapshot: MainChatRuntimeSnapshotBridge?,
        conversationId targetConversationId: UUID?
    ) -> MainChatRuntimeSnapshotBridge? {
        preferredConversationRuntimeSnapshot(
            baseSnapshot: baseSnapshot,
            conversationTurnState: targetConversationId.flatMap {
                conversationRuntime.activeTurnStateByConversation[$0]
            },
            conversationId: targetConversationId
        )
    }
}
