import Foundation
import CoderEngine

extension ChatStore {
func createCheckpoint(
    for conversationId: UUID?,
    gitStates: [ConversationCheckpointGitState],
    planConversationIdForSnapshot: UUID? = nil
) {
    guard let conversationId else { return }
    guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    let linkedPlanConversationId: UUID? = {
        guard let planConversationIdForSnapshot else { return nil }
        return planConversationIdForSnapshot == conversationId ? nil : planConversationIdForSnapshot
    }()
    let checkpoint = ConversationCheckpoint(
        messageCount: conversations[conversationIndex].messages.count,
        planBoardSnapshot: planBoards[conversationId],
        linkedPlanConversationId: linkedPlanConversationId,
        linkedPlanBoardSnapshot: linkedPlanConversationId.flatMap { planBoards[$0] },
        gitStates: gitStates
    )
    if shouldSkipRustStoreBootstrapForTests(environment: ProcessInfo.processInfo.environment) {
        conversations[conversationIndex].checkpoints.append(checkpoint)
    } else {
        _ = applyRustStoreAction("create_checkpoint") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.checkpoint = RustMainChatStoreAdapter.checkpointSnapshot(checkpoint)
        }
    }
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
    guard let conversationId else { return false }
    let ok: Bool
    if shouldSkipRustStoreBootstrapForTests(environment: ProcessInfo.processInfo.environment) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationId }),
              let checkpointIndex = conversations[conversationIndex].checkpoints.lastIndex(where: { $0.id == checkpointId })
        else {
            return false
        }
        let checkpoint = conversations[conversationIndex].checkpoints[checkpointIndex]
        guard checkpoint.messageCount <= conversations[conversationIndex].messages.count else {
            return false
        }
        conversations[conversationIndex].messages = Array(conversations[conversationIndex].messages.prefix(checkpoint.messageCount))
        if let board = checkpoint.planBoardSnapshot {
            planBoards[conversationId] = board
        } else {
            planBoards.removeValue(forKey: conversationId)
        }
        if let linkedPlanConversationId = checkpoint.linkedPlanConversationId {
            if let board = checkpoint.linkedPlanBoardSnapshot {
                planBoards[linkedPlanConversationId] = board
            } else {
                planBoards.removeValue(forKey: linkedPlanConversationId)
            }
        }
        conversations[conversationIndex].checkpoints = Array(conversations[conversationIndex].checkpoints.prefix(checkpointIndex))
        ok = true
    } else {
        ok = applyRustStoreAction("rewind_to_checkpoint") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.checkpointId = checkpointId.uuidString.lowercased()
        }
    }
    if ok {
        saveConversations()
        savePlanBoards()
    }
    return ok
}

func trimFutureCheckpoints(conversationId: UUID?, maxMessageCount: Int) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    conversations[idx].checkpoints.removeAll { $0.messageCount > maxMessageCount }
    saveConversations()
}

@discardableResult
func rewindConversationToMessageCount(_ messageCount: Int, conversationId: UUID?) -> Bool {
    guard let conversationId else { return false }
    let ok: Bool
    if shouldSkipRustStoreBootstrapForTests(environment: ProcessInfo.processInfo.environment) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationId }),
              messageCount >= 0,
              messageCount <= conversations[conversationIndex].messages.count else {
            return false
        }
        conversations[conversationIndex].messages = Array(conversations[conversationIndex].messages.prefix(messageCount))
        conversations[conversationIndex].checkpoints.removeAll { $0.messageCount > messageCount }
        if let lastCheckpoint = conversations[conversationIndex].checkpoints.last {
            if let board = lastCheckpoint.planBoardSnapshot {
                planBoards[conversationId] = board
            } else {
                planBoards.removeValue(forKey: conversationId)
            }
            if let linkedPlanConversationId = lastCheckpoint.linkedPlanConversationId {
                if let board = lastCheckpoint.linkedPlanBoardSnapshot {
                    planBoards[linkedPlanConversationId] = board
                } else {
                    planBoards.removeValue(forKey: linkedPlanConversationId)
                }
            }
        } else {
            planBoards.removeValue(forKey: conversationId)
        }
        ok = true
    } else {
        ok = applyRustStoreAction("rewind_to_message_count") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.messageCount = messageCount
        }
    }
    if ok {
        saveConversations()
        savePlanBoards()
    }
    return ok
}
}
