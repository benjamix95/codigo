import Foundation
import CoderEngine

extension ChatStore {
func createCheckpoint(
    for conversationId: UUID?,
    gitStates: [ConversationCheckpointGitState],
    planConversationIdForSnapshot: UUID? = nil
) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    let linkedPlanConversationId: UUID? = {
        guard let planConversationIdForSnapshot else { return nil }
        return planConversationIdForSnapshot == conversations[idx].id ? nil : planConversationIdForSnapshot
    }()
    let checkpoint = ConversationCheckpoint(
        messageCount: conversations[idx].messages.count,
        planBoardSnapshot: planBoards[conversations[idx].id],
        linkedPlanConversationId: linkedPlanConversationId,
        linkedPlanBoardSnapshot: linkedPlanConversationId.flatMap { planBoards[$0] },
        gitStates: gitStates
    )
    conversations[idx].checkpoints.append(checkpoint)
    saveConversations()
}

func canRewind(conversationId: UUID?) -> Bool {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return false }
    return !conversations[idx].checkpoints.isEmpty
}

func previousCheckpoint(conversationId: UUID?) -> ConversationCheckpoint? {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return nil }
    return conversations[idx].checkpoints.last
}

func checkpoint(forMessageIndex messageIndex: Int, conversationId: UUID?) -> ConversationCheckpoint? {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return nil }
    return conversations[idx].checkpoints.last { $0.messageCount == (messageIndex + 1) }
}

@discardableResult
func rewindConversationState(to checkpointId: UUID, conversationId: UUID?) -> Bool {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return false }
    guard let cpIdx = conversations[idx].checkpoints.lastIndex(where: { $0.id == checkpointId }) else { return false }
    let checkpoint = conversations[idx].checkpoints[cpIdx]
    guard checkpoint.messageCount <= conversations[idx].messages.count else { return false }

    conversations[idx].messages = Array(conversations[idx].messages.prefix(checkpoint.messageCount))
    if let snapshot = checkpoint.planBoardSnapshot {
        planBoards[conversations[idx].id] = snapshot
    } else {
        planBoards.removeValue(forKey: conversations[idx].id)
    }
    if let linkedConversationId = checkpoint.linkedPlanConversationId {
        if let linkedSnapshot = checkpoint.linkedPlanBoardSnapshot {
            planBoards[linkedConversationId] = linkedSnapshot
        } else {
            planBoards.removeValue(forKey: linkedConversationId)
        }
    }
    conversations[idx].checkpoints = Array(conversations[idx].checkpoints.prefix(cpIdx))
    saveConversations()
    savePlanBoards()
    return true
}

func trimFutureCheckpoints(conversationId: UUID?, maxMessageCount: Int) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    conversations[idx].checkpoints.removeAll { $0.messageCount > maxMessageCount }
    saveConversations()
}

@discardableResult
func rewindConversationToMessageCount(_ messageCount: Int, conversationId: UUID?) -> Bool {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return false }
    guard messageCount >= 0, messageCount <= conversations[idx].messages.count else { return false }
    conversations[idx].messages = Array(conversations[idx].messages.prefix(messageCount))
    conversations[idx].checkpoints.removeAll { $0.messageCount > messageCount }
    // Restore the plan board from the most recent remaining checkpoint,
    // or clear it if no checkpoints remain.
    if let lastCheckpoint = conversations[idx].checkpoints.last,
       let snapshot = lastCheckpoint.planBoardSnapshot {
        planBoards[conversations[idx].id] = snapshot
    } else {
        planBoards.removeValue(forKey: conversations[idx].id)
    }
    if let lastCheckpoint = conversations[idx].checkpoints.last,
       let linkedConversationId = lastCheckpoint.linkedPlanConversationId {
        if let linkedSnapshot = lastCheckpoint.linkedPlanBoardSnapshot {
            planBoards[linkedConversationId] = linkedSnapshot
        } else {
            planBoards.removeValue(forKey: linkedConversationId)
        }
    }
    saveConversations()
    savePlanBoards()
    return true
}
}
