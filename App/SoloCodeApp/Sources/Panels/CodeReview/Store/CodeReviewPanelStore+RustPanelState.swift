import CoderEngine
import Foundation

enum ReviewPanelStateRustAdapter {
    static func reduce(
        snapshot: CodeReviewSessionSnapshot
    ) -> ReviewPanelRustPanelState? {
        let response: ReviewPanelReduceResponse? = ReviewCoreBridge.call(
            functionName: "review_core_reduce_panel_state",
            request: ReviewPanelReduceRequest(snapshot: snapshot)
        )
        guard response?.error == nil else { return nil }
        return response?.panelState
    }

    static let runtimeUnavailableMessage = "Rust review panel runtime required but unavailable."
}

struct ReviewPanelReduceRequest: Encodable {
    let schemaVersion: Int = 1
    let operation: String = "derive_review_panel_state"
    let snapshot: CodeReviewSessionSnapshot
}

struct ReviewPanelReduceResponse: Decodable {
    let schemaVersion: Int
    let error: ReviewPanelReduceError?
    let panelState: ReviewPanelRustPanelState?
}

struct ReviewPanelReduceError: Decodable {
    let code: String
    let message: String
}

struct ReviewPanelRustPanelState: Decodable {
    let liveCandidateIds: [String]
    let verifiedFindingIds: [String]
    let publishReadyFindingIds: [String]
    let publishedFindingIds: [String]
    let publishedSeverityCounts: [String: Int]
    let pipelinePhase: String
    let progressPercent: Int
    let stepsCompleted: Int
    let stepsTotal: Int
    let toolsTotal: Int
    let toolsCompleted: Int
    let toolsRunning: Int
    let candidateCount: Int
    let verifiedCount: Int
    let publishedFindingCount: Int
    let hiddenFindingCount: Int
    let verificationGateReady: Bool
    let patchGateReady: Bool
    let bundleModes: [String]
    let toolExecutions: [ReviewPanelRustToolExecution]
    let isTerminal: Bool
    let phaseLedger: [ReviewPipelinePhaseLedgerEntry]
    let fileLedger: [ReviewPipelineFileLedgerEntry]
    let warmState: String
    let emptyStateTitle: String
    let emptyStateSubtitle: String

    func makePipelineJobState() -> ReviewPipelineJobState {
        ReviewPipelineJobState(
            title: "Stato revisione",
            phase: pipelinePhase,
            progressPercent: progressPercent,
            stepsCompleted: stepsCompleted,
            stepsTotal: stepsTotal,
            toolsTotal: toolsTotal,
            toolsCompleted: toolsCompleted,
            toolsRunning: toolsRunning,
            candidateCount: candidateCount,
            verifiedCount: verifiedCount,
            publishedFindingCount: publishedFindingCount,
            hiddenFindingCount: hiddenFindingCount,
            gates: [
                ReviewPipelineGateState(title: "Verification", isReady: verificationGateReady),
                ReviewPipelineGateState(title: "Patch", isReady: patchGateReady),
            ],
            tools: toolExecutions.map {
                ReviewPipelineToolExecution(
                    id: $0.id,
                    title: ReviewPipelineJobStateBuilder.displayTitle(for: $0.id),
                    status: $0.status.reviewToolStatus,
                    findingsCount: $0.findingsCount
                )
            },
            phaseLedger: phaseLedger,
            bundleModes: bundleModes,
            isTerminal: isTerminal
        )
    }
}

struct ReviewPanelRustToolExecution: Decodable {
    let id: String
    let status: String
    let findingsCount: Int
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

extension String {
    var reviewToolStatus: ReviewPipelineToolExecution.Status {
        switch self {
        case "completed":
            return .completed
        case "running":
            return .running
        default:
            return .pending
        }
    }

    var reviewPanelWarmState: ReviewPanelWarmState {
        switch self {
        case "warming":
            return .warming
        case "failed":
            return .failed
        case "idle":
            return .idle
        default:
            return .ready
        }
    }
}

extension Dictionary where Key == String, Value == Int {
    var findingSeverityCounts: [FindingSeverity: Int] {
        reduce(into: [FindingSeverity: Int]()) { partialResult, entry in
            if let severity = FindingSeverity(rawValue: entry.key) {
                partialResult[severity] = entry.value
            }
        }
    }
}
