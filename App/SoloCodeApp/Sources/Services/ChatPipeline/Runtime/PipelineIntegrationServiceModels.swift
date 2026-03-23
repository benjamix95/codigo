import CoderEngine
import Foundation

struct PipelineConversationSnapshot {
    let currentJobId: String
    let providerId: String
    let assistantMessageId: UUID
    let planConversationId: UUID?
    let jobState: JobState
    let completedTasks: Int
    let totalTasks: Int
    let isRunning: Bool
    let lastError: String?
    let circuitBreakerActive: Bool
    /// Start time of the job, for elapsed timer display.
    let jobStartTime: Date
}

@MainActor
final class PipelineConversationRuntime {
    enum TeardownState: Equatable {
        case running
        case finalizing
        case finished
    }

    let conversationId: UUID
    let facade: PipelineFacade
    var assistantMessageId: UUID
    let planConversationId: UUID?
    let onCompletion: ((PipelineCompletionContext) -> Void)?
    let rawEventHandler: ((_ type: String, _ payload: [String: String], _ providerId: String, _ conversationId: UUID?) -> Void)?

    var currentJobId: String
    let providerId: String
    var jobState: JobState
    var completedTasks: Int
    var totalTasks: Int
    var isRunning: Bool
    var lastError: String?
    var circuitBreakerActive: Bool
    var wasCancelled: Bool
    var chatTurnState: ChatTurnState
    var nextPipelineSequence: Int
    var activeStreamTask: Task<Void, Never>?
    var teardownState: TeardownState
    let jobStartTime: Date

    init(
        conversationId: UUID,
        facade: PipelineFacade,
        jobId: String,
        providerId: String,
        assistantMessageId: UUID,
        planConversationId: UUID?,
        onCompletion: ((PipelineCompletionContext) -> Void)?,
        rawEventHandler: ((_ type: String, _ payload: [String: String], _ providerId: String, _ conversationId: UUID?) -> Void)?
    ) {
        self.conversationId = conversationId
        self.facade = facade
        self.currentJobId = jobId
        self.providerId = providerId
        self.assistantMessageId = assistantMessageId
        self.planConversationId = planConversationId
        self.onCompletion = onCompletion
        self.rawEventHandler = rawEventHandler
        self.jobState = .intake
        self.completedTasks = 0
        self.totalTasks = 0
        self.isRunning = true
        self.lastError = nil
        self.circuitBreakerActive = false
        self.wasCancelled = false
        self.chatTurnState = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: assistantMessageId.uuidString,
            providerId: providerId
        )
        self.nextPipelineSequence = 1
        self.teardownState = .running
        self.jobStartTime = Date()
    }

    var snapshot: PipelineConversationSnapshot {
        PipelineConversationSnapshot(
            currentJobId: currentJobId,
            providerId: providerId,
            assistantMessageId: assistantMessageId,
            planConversationId: planConversationId,
            jobState: jobState,
            completedTasks: completedTasks,
            totalTasks: totalTasks,
            isRunning: isRunning,
            lastError: lastError,
            circuitBreakerActive: circuitBreakerActive,
            jobStartTime: jobStartTime
        )
    }

    func retargetAssistantMessage(
        assistantMessageId: UUID,
        turnId: String
    ) {
        self.assistantMessageId = assistantMessageId
        self.chatTurnState = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId,
            providerId: providerId
        )
        self.nextPipelineSequence = 1
    }

    var isTearDownFinalized: Bool {
        teardownState == .finished
    }

    @discardableResult
    func beginTeardownIfNeeded() -> Bool {
        switch teardownState {
        case .running:
            teardownState = .finalizing
            isRunning = false
            return true
        case .finalizing, .finished:
            return false
        }
    }

    func finishTeardown() {
        teardownState = .finished
        activeStreamTask = nil
        isRunning = false
    }
}
