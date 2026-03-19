import CoderEngine
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
        if !setActiveChatThread(threadId),
           !ReviewCoreBridge.isEnabled {
            activeChatThreadId = threadId
        }
        selectTab(.chat)
    }

    func selectChatThread(_ threadId: String) {
        chatSessionStore.selectThread(threadId, for: chatSessionKey)
        if !setActiveChatThread(threadId),
           !ReviewCoreBridge.isEnabled {
            activeChatThreadId = threadId
        }
        selectTab(.chat)
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
            if let activeThreadId = conversation.activeThreadId {
                if !setActiveChatThread(activeThreadId),
                   !ReviewCoreBridge.isEnabled {
                    activeChatThreadId = activeThreadId
                }
            } else if !clearActiveChatThread(),
                      !ReviewCoreBridge.isEnabled {
                activeChatThreadId = nil
            }
        }
        let activeState = conversation.activeThreadId.flatMap { activeId in
            conversation.threads.first(where: { $0.id == activeId })?.sessionState
        } ?? .empty
        applyChatSessionState(activeState)
    }

    func extractAndMergeChatFindingsWithRust(
        content: String,
        existing: [CodeReviewFinding]
    ) -> ReviewCoreChatExtractionPayload? {
        let request = ReviewCoreChatExtractionRequest(
            schemaVersion: 1,
            content: content,
            existingFindings: existing
        )
        let response: ReviewCoreChatExtractionResponse? = ReviewCoreBridge.call(
            functionName: "review_core_panel_chat_extract",
            request: request
        )
        guard response?.error == nil,
              let payload = response?.payload,
              payload.foundBlock else {
            return nil
        }
        return payload
    }

    func syncStructuredFindingsFromChatResponse(
        messageId: UUID,
        sessionId: String? = nil
    ) async {
        guard let index = chatMessages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        let originalContent = chatMessages[index].content
        guard let sessionId = sessionId ?? selectedSessionId,
              let snapshot = taskActivityStore.codeReviewSnapshot(
                sessionId: sessionId,
                conversationId: conversationId
              ),
              let extraction = extractAndMergeChatFindingsWithRust(
                content: originalContent,
                existing: snapshot.findings
              ) else {
            return
        }

        chatMessages[index].content = extraction.visibleContent
        persistChatState()

        guard extraction.insertedCount > 0 else {
            return
        }

        let existingCount = snapshot.findings.count
        let inserted = Array(extraction.findings.dropFirst(existingCount))
        let events = inserted.map {
            CodeReviewSessionEvent.findingAdded(
                findingId: $0.id,
                severity: $0.severity.rawValue,
                filePath: $0.filePath
            )
        }
        let updated = snapshot.copying(
            findings: extraction.findings,
            events: snapshot.events + events,
            outcome: snapshot.copying(findings: extraction.findings).buildOutcomeSummary()
        )
        taskActivityStore.ingestCodeReviewSnapshot(
            updated,
            conversationId: conversationId
        )
        appendPanelSystemMessage(
            "Synced \(extraction.insertedCount) finding(s) from chat into the Findings tab.",
            kind: .statusNote,
            selectChatTab: false
        )
    }
}

private extension CodeReviewPanelStore {
    func isIncomingChatConversationStale(
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

struct ReviewCoreChatExtractionPayload {
    let foundBlock: Bool
    let visibleContent: String
    let findings: [CodeReviewFinding]
    let insertedCount: Int
    let extractedCount: Int
}

private struct ReviewCoreChatExtractionRequest: Encodable {
    let schemaVersion: Int
    let content: String
    let existingFindings: [CodeReviewFinding]
}

private struct ReviewCoreChatExtractionResponse: Decodable {
    let schemaVersion: Int
    let error: ReviewPanelReduceError?
    let foundBlock: Bool
    let visibleContent: String
    let findings: [CodeReviewFinding]
    let insertedCount: Int
    let extractedCount: Int

    var payload: ReviewCoreChatExtractionPayload {
        ReviewCoreChatExtractionPayload(
            foundBlock: foundBlock,
            visibleContent: visibleContent,
            findings: findings,
            insertedCount: insertedCount,
            extractedCount: extractedCount
        )
    }
}
