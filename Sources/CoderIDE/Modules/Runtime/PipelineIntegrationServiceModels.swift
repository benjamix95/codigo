import CoderEngine
import Foundation

struct PipelineConversationSnapshot {
    let currentJobId: String
    let assistantMessageId: UUID
    let planConversationId: UUID?
    let jobState: JobState
    let completedTasks: Int
    let totalTasks: Int
    let isRunning: Bool
    let lastError: String?
    let circuitBreakerActive: Bool
}

@MainActor
final class PipelineConversationRuntime {
    let conversationId: UUID
    let facade: PipelineFacade
    let assistantMessageId: UUID
    let planConversationId: UUID?
    let onCompletion: ((PipelineCompletionContext) -> Void)?

    var currentJobId: String
    var jobState: JobState
    var completedTasks: Int
    var totalTasks: Int
    var isRunning: Bool
    var lastError: String?
    var circuitBreakerActive: Bool
    var wasCancelled: Bool
    var accumulatedText: [String: String]
    var activeStreamTask: Task<Void, Never>?
    let jobStartTime: Date

    init(
        conversationId: UUID,
        facade: PipelineFacade,
        jobId: String,
        assistantMessageId: UUID,
        planConversationId: UUID?,
        onCompletion: ((PipelineCompletionContext) -> Void)?
    ) {
        self.conversationId = conversationId
        self.facade = facade
        self.currentJobId = jobId
        self.assistantMessageId = assistantMessageId
        self.planConversationId = planConversationId
        self.onCompletion = onCompletion
        self.jobState = .intake
        self.completedTasks = 0
        self.totalTasks = 0
        self.isRunning = true
        self.lastError = nil
        self.circuitBreakerActive = false
        self.wasCancelled = false
        self.accumulatedText = [:]
        self.jobStartTime = Date()
    }

    var snapshot: PipelineConversationSnapshot {
        PipelineConversationSnapshot(
            currentJobId: currentJobId,
            assistantMessageId: assistantMessageId,
            planConversationId: planConversationId,
            jobState: jobState,
            completedTasks: completedTasks,
            totalTasks: totalTasks,
            isRunning: isRunning,
            lastError: lastError,
            circuitBreakerActive: circuitBreakerActive
        )
    }
}
