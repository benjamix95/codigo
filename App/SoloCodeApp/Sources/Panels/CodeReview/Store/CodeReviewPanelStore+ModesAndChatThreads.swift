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

    var currentChatSessionState: ReviewPanelChatSessionState {
        ReviewPanelChatSessionState(
            messages: chatMessages,
            isProcessing: isChatProcessing,
            startedAt: chatStartedAt
        )
    }

    var currentChatConversationState: ReviewPanelChatConversationState {
        ReviewPanelChatConversationState(
            threads: chatThreads,
            activeThreadId: activeChatThreadId
        )
    }

    func createNewChatThread(title: String? = nil) {
        let threadId = chatSessionStore.createThread(for: chatSessionKey, title: title)
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
        guard currentChatSessionState != state else { return }
        if chatMessages != state.messages {
            chatMessages = state.messages
        }
        if isChatProcessing != state.isProcessing {
            isChatProcessing = state.isProcessing
        }
        if chatStartedAt != state.startedAt {
            chatStartedAt = state.startedAt
        }
    }

    // MARK: - Chat Conversation Handling

    /// Handles incoming chat conversation updates from the session store.
    /// Defers the actual state mutation to avoid view-update reentrancy.
    func handleIncomingChatConversation(_ conversation: ReviewPanelChatConversationState) {
        guard currentChatConversationState != conversation else { return }
        guard !isIncomingChatConversationStale(conversation) else { return }
        pendingChatConversationApplyTask?.cancel()
        pendingChatConversationApplyTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            self.pendingChatConversationApplyTask = nil
            self.applyChatConversationState(conversation)
        }
    }

    func applyChatConversationState(_ conversation: ReviewPanelChatConversationState) {
        guard currentChatConversationState != conversation else { return }
        if chatThreads != conversation.threads {
            chatThreads = conversation.threads
        }
        if activeChatThreadId != conversation.activeThreadId {
            activeChatThreadId = conversation.activeThreadId
        }
        let activeState = conversation.activeThreadId.flatMap { activeId in
            conversation.threads.first(where: { $0.id == activeId })?.sessionState
        } ?? .empty
        applyChatSessionState(activeState)
    }

    private func isIncomingChatConversationStale(
        _ conversation: ReviewPanelChatConversationState
    ) -> Bool {
        let incomingState = conversation.activeThreadId.flatMap { activeId in
            conversation.threads.first(where: { $0.id == activeId })?.sessionState
        } ?? .empty
        let currentState = currentChatSessionState

        guard !currentState.messages.isEmpty else { return false }
        guard incomingState.messages.count >= currentState.messages.count else { return true }

        let incomingById = Dictionary(
            uniqueKeysWithValues: incomingState.messages.map { ($0.id, $0) }
        )

        for current in currentState.messages {
            guard let incoming = incomingById[current.id] else { return true }
            if current.presentation != nil && incoming.presentation == nil {
                return true
            }
            if current.content.count > incoming.content.count {
                return true
            }
            if !current.isStreaming && incoming.isStreaming {
                return true
            }
        }
        return false
    }
}
