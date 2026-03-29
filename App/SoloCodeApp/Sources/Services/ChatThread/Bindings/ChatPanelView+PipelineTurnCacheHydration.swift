import CoderEngine
import Foundation
import SwiftUI

extension ChatPanelView {
    /// Ripopola `pipelineTurnStateByAssistantMessageId` dai messaggi **persistiti** nel `ChatStore`
    /// quando la RAM è stata persa (ricreazione `ChatPanelView`, ecc.) ma i blocchi hanno già `toolMarker`.
    /// Senza questo, solo il turno attivo ha merge ricco (**H36**) e un messaggio history con molti trace resta **H26**.
    @MainActor
    internal func hydratePipelineTurnCacheFromPersistedAssistantMessagesIfNeeded() {
        guard let cid = conversationId,
              let conv = chatStore.conversation(for: cid)
        else { return }

        var hydratedIds: [UUID] = []
        var hydratedMarkers = 0
        for msg in conv.messages where msg.role == .assistant {
            let markerCount = msg.blocks?.filter { $0.kind == .toolMarker }.count ?? 0
            guard markerCount > 0 else { continue }
            if conversationRuntime.pipelineTurnStateByAssistantMessageId[msg.id] != nil { continue }

            let state = restoredChatTurnStateFromPersistedAssistantMessage(
                conversationId: conv.id,
                message: msg
            )
            conversationRuntime.cachePipelineTurnStateForAssistantMessage(state)
            hydratedIds.append(msg.id)
            hydratedMarkers += markerCount
        }
        // #region agent log
        if !hydratedIds.isEmpty {
            StreamingTimelineMergeDebug72.logPipelineTurnCacheHydratedFromStore(
                conversationId: cid,
                hydratedMessageIds: hydratedIds,
                totalMarkerCount: hydratedMarkers
            )
        }
        // #endregion
    }
}
