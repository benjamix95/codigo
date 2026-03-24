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
    var pendingDebugEventsByConversation: [UUID: [NormalizedEvent]] = [:]

    // MARK: - Fallback

    var fallbackTurnStartWorkItemsByConversation: [UUID: DispatchWorkItem] = [:]
}
