import Foundation

extension CodeReviewPanelStore {
    static func chatSessionKey(conversationId: UUID?) -> String {
        conversationId?.uuidString.lowercased() ?? "workspace-review-panel"
    }

    var orderedSelectedModes: [CodeReviewPanelMode] {
        CodeReviewPanelMode.allCases.filter { selectedModes.contains($0) }
    }

    var primarySelectedMode: CodeReviewPanelMode {
        orderedSelectedModes.first ?? .standard
    }

    func hasSelectedMode(_ mode: CodeReviewPanelMode) -> Bool {
        selectedModes.contains(mode)
    }

    func toggleModeSelection(_ mode: CodeReviewPanelMode) {
        if selectedModes.contains(mode) {
            if selectedModes.count > 1 {
                selectedModes.remove(mode)
            }
        } else {
            selectedModes.insert(mode)
        }
    }

    var chatSessionKey: String {
        Self.chatSessionKey(conversationId: conversationId)
    }

    func createNewChatThread() {
        let threadId = chatSessionStore.createThread(for: chatSessionKey)
        activeChatThreadId = threadId
        selectedTab = .chat
    }

    func selectChatThread(_ threadId: String) {
        chatSessionStore.selectThread(threadId, for: chatSessionKey)
        selectedTab = .chat
    }

    func archiveChatThread(_ threadId: String) {
        chatSessionStore.archiveThread(threadId, for: chatSessionKey)
    }

    func restoreChatThread(_ threadId: String) {
        chatSessionStore.restoreThread(threadId, for: chatSessionKey)
    }

    func deleteChatThread(_ threadId: String) {
        chatSessionStore.deleteThread(threadId, for: chatSessionKey)
    }

    func applyChatSessionState(_ state: ReviewPanelChatSessionState) {
        chatMessages = state.messages
        isChatProcessing = state.isProcessing
        chatStartedAt = state.startedAt
    }

    func applyChatConversationState(_ conversation: ReviewPanelChatConversationState) {
        chatThreads = conversation.threads
        activeChatThreadId = conversation.activeThreadId
        let activeState = conversation.activeThreadId.flatMap { activeId in
            conversation.threads.first(where: { $0.id == activeId })?.sessionState
        } ?? .empty
        applyChatSessionState(activeState)
    }
}
