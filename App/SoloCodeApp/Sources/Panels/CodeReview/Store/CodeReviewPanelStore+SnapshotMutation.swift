import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func makeRuntimeStateSnapshot() -> ReviewPanelRuntimeStateSnapshot {
        ReviewPanelRuntimeStateSnapshot(
            selectedTab: selectedTab.rawValue,
            isRunning: isRunning,
            runStartedAt: runStartedAt,
            frozenTimerText: frozenTimerText,
            lastError: lastError,
            chatMessages: chatMessages,
            isChatProcessing: isChatProcessing,
            chatStartedAt: chatStartedAt,
            responseMessageIds: Dictionary(
                uniqueKeysWithValues: responseMessageIds.map {
                    ($0.key.uuidString, $0.value.uuidString)
                }
            ),
            finishedReviewRunActivityIds: finishedReviewRunActivityIds
                .map(\.uuidString)
                .sorted()
        )
    }

    func applyRuntimeState(_ state: ReviewPanelRuntimeStateSnapshot) {
        pendingChatConversationApplyTask?.cancel()
        pendingChatConversationApplyTask = nil
        if let tab = CodeReviewTab(rawValue: state.selectedTab) {
            selectedTab = tab
        }
        isRunning = state.isRunning
        runStartedAt = state.runStartedAt
        frozenTimerText = state.frozenTimerText
        lastError = state.lastError
        chatMessages = state.chatMessages
        isChatProcessing = state.isChatProcessing
        chatStartedAt = state.chatStartedAt
        responseMessageIds = state.responseMessageIds.reduce(into: [:]) { partialResult, entry in
            guard let key = UUID(uuidString: entry.key),
                  let value = UUID(uuidString: entry.value) else { return }
            partialResult[key] = value
        }
        finishedReviewRunActivityIds = Set(
            state.finishedReviewRunActivityIds.compactMap(UUID.init(uuidString:))
        )
        finalizeReviewRunMessagesIfNeeded()
        persistChatState()
    }

    func finalizeReviewRunMessagesIfNeeded() {
        for index in chatMessages.indices where
            chatMessages[index].kind == .reviewRun &&
            !chatMessages[index].isStreaming &&
            chatMessages[index].presentation == nil
        {
            ReviewPanelChatMessageFactory.finalizeReviewRunMessage(&chatMessages[index])
        }
    }

    func applyPanelChatStart(
        assistantId: UUID,
        startedAt: Date
    ) -> Bool {
        let response: ReviewPanelRuntimeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_panel_chat_start",
            request: ReviewPanelChatStartRequest(
                state: makeRuntimeStateSnapshot(),
                assistantMessageId: assistantId.uuidString,
                startedAt: startedAt,
                messageTimestamp: startedAt
            )
        )
        guard response?.error == nil, let state = response?.state else {
            return false
        }
        applyRuntimeState(state)
        return true
    }

    func applyPanelChatFinish(
        assistantId: UUID?,
        fallbackContent: String?,
        error: String?,
        wasCancelled: Bool,
        finishAllStreaming: Bool
    ) -> ReviewPanelRuntimeOutcome? {
        let response: ReviewPanelRuntimeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_panel_chat_finish",
            request: ReviewPanelChatFinishRequest(
                state: makeRuntimeStateSnapshot(),
                assistantMessageId: assistantId?.uuidString,
                finishedAt: Date(),
                errorMessage: error,
                wasCancelled: wasCancelled,
                fallbackContent: fallbackContent,
                finishAllStreaming: finishAllStreaming,
                suggestedVerdictMessageId: UUID().uuidString
            )
        )
        guard response?.error == nil, let state = response?.state else {
            isChatProcessing = false
            chatStartedAt = nil
            persistChatState()
            return ReviewPanelRuntimeOutcome(
                status: wasCancelled ? "cancelled" : "failed",
                message: error ?? ReviewPanelStateRustAdapter.runtimeUnavailableMessage
            )
        }
        applyRuntimeState(state)
        return response?.outcome
    }

    func mutateSnapshotUsingRust(
        sessionId: String,
        action: String,
        payload: [String: String]
    ) async {
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else { return }

        guard let mutation: ReviewPanelCommandMutationResponse = ReviewCoreBridge.call(
            functionName: "review_core_command_mutate_snapshot",
            request: ReviewPanelCommandMutationRequest(
                schemaVersion: 1,
                action: action,
                snapshot: snapshot,
                payload: payload
            )
        ),
              !mutation.isError,
              let findings = mutation.findings,
              let events = mutation.events else {
            return
        }

        let updated = snapshot.copying(
            findings: findings,
            events: events,
            outcome: snapshot.copying(findings: findings).buildOutcomeSummary()
        )
        taskActivityStore.scheduleCodeReviewSnapshotIngest(
            updated,
            conversationId: conversationId
        )
    }
}

private struct ReviewPanelCommandMutationRequest: Encodable {
    let schemaVersion: Int
    let action: String
    let snapshot: CodeReviewSessionSnapshot
    let payload: [String: String]
}

private struct ReviewPanelCommandMutationResponse: Decodable {
    let isError: Bool
    let message: String?
    let findings: [CodeReviewFinding]?
    let events: [CodeReviewSessionEvent]?
}

struct ReviewPanelRuntimeStateSnapshot: Codable {
    let selectedTab: String
    let isRunning: Bool
    let runStartedAt: Date?
    let frozenTimerText: String?
    let lastError: String?
    let chatMessages: [ReviewPanelMessage]
    let isChatProcessing: Bool
    let chatStartedAt: Date?
    let responseMessageIds: [String: String]
    let finishedReviewRunActivityIds: [String]
}

struct ReviewPanelRuntimeResponse: Decodable {
    let schemaVersion: Int
    let error: ReviewPanelReduceError?
    let state: ReviewPanelRuntimeStateSnapshot?
    let outcome: ReviewPanelRuntimeOutcome?
}

struct ReviewPanelRuntimeOutcome: Decodable {
    let status: String
    let message: String?
}

struct ReviewPanelRuntimeEventEnvelope: Encodable {
    let kind: String
    let text: String?
    let eventType: String?
    let payload: [String: String]
}

private struct ReviewPanelChatStartRequest: Encodable {
    let schemaVersion: Int = 1
    let state: ReviewPanelRuntimeStateSnapshot
    let assistantMessageId: String
    let startedAt: Date
    let messageTimestamp: Date
}

private struct ReviewPanelChatFinishRequest: Encodable {
    let schemaVersion: Int = 1
    let state: ReviewPanelRuntimeStateSnapshot
    let assistantMessageId: String?
    let finishedAt: Date
    let errorMessage: String?
    let wasCancelled: Bool
    let fallbackContent: String?
    let finishAllStreaming: Bool
    let suggestedVerdictMessageId: String?
}
