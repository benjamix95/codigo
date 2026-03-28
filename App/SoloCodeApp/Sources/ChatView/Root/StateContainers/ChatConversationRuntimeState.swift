import CoderEngine
import Foundation
import SwiftUI

// MARK: - ChatConversationRuntimeState

/// Groups turn-state, pipeline, task-activity, auto-todo, and debug-local
/// @State properties that track per-conversation runtime data.
struct ChatConversationRuntimeState {

    // MARK: - Turn & Pipeline

    var activeTurnStateByConversation: [UUID: ChatTurnState] = [:]
    var renderSnapshotByConversation: [UUID: ChatTurnState] = [:]
    /// Ultimo `ChatTurnState` noto per messaggio assistente (sopravvive al cambio turno su `activeTurnStateByConversation`).
    /// Serve al merge timeline per righe history con trace ma blocchi store senza `toolMarker` (H26).
    var pipelineTurnStateByAssistantMessageId: [UUID: ChatTurnState] = [:]

    mutating func cachePipelineTurnStateForAssistantMessage(_ state: ChatTurnState) {
        pipelineTurnStateByAssistantMessageId[state.assistantMessageId] = state
    }
    var collapsedArtifactsByTurn: [String: Set<String>] = [:]
    var pipelineEventSequenceByConversation: [UUID: Int] = [:]

    // MARK: - Task Activity

    var pendingTaskActivities: [TaskActivity] = []
    var pendingInstantGreps: [InstantGrepResult] = []
    var taskFlushTask: Task<Void, Never>?

    // MARK: - Auto-Todo

    var autoTodoRuntimeStateByMessage: [String: MainChatUIAutoTodoRuntimeStateBridge] = [:]
    var didReceiveExplicitTodoByMessage: Set<UUID> = []

    // MARK: - Debug Local

    var debugStateByConversation: [UUID: DebugStore.SessionSnapshot] = [:]

    // MARK: - Fallback

    var fallbackTurnStartWorkItemsByConversation: [UUID: DispatchWorkItem] = [:]
}
