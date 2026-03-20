import Foundation
import CoderEngine

extension ChatStore {
func createCheckpoint(
    for conversationId: UUID?,
    gitStates: [ConversationCheckpointGitState],
    planConversationIdForSnapshot: UUID? = nil
) {
    guard let conversationId else { return }
    let linkedPlanConversationId: UUID? = {
        guard let planConversationIdForSnapshot else { return nil }
        return planConversationIdForSnapshot == conversationId ? nil : planConversationIdForSnapshot
    }()
    let checkpoint = ConversationCheckpoint(
        messageCount: 0,
        planBoardSnapshot: planBoards[conversationId],
        linkedPlanConversationId: linkedPlanConversationId,
        linkedPlanBoardSnapshot: linkedPlanConversationId.flatMap { planBoards[$0] },
        gitStates: gitStates
    )
    _ = applyRustStoreAction("create_checkpoint") { request in
        request.conversationId = conversationId.uuidString.lowercased()
        request.checkpoint = RustMainChatStoreAdapter.checkpointSnapshot(checkpoint)
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
    let ok = applyRustStoreAction("rewind_to_checkpoint") { request in
        request.conversationId = conversationId.uuidString.lowercased()
        request.checkpointId = checkpointId.uuidString.lowercased()
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
    let ok = applyRustStoreAction("rewind_to_message_count") { request in
        request.conversationId = conversationId.uuidString.lowercased()
        request.messageCount = messageCount
    }
    if ok {
        saveConversations()
        savePlanBoards()
    }
    return ok
}
}
