import CoderEngine
import Foundation
import SwiftUI

// MARK: - PipelineCompletionContext

struct PipelineCompletionContext {
    let jobId: String
    let planConversationId: UUID?
    let conversationId: UUID
    let completedTasks: Int
    let totalTasks: Int
    let durationMs: Int
    let success: Bool
}

// MARK: - PipelineIntegrationService

/// Service che collega la pipeline al layer UI di CoderIDE.
/// Consuma `PipelineUIEvent` e aggiorna ChatStore, TaskActivityStore,
/// SwarmProgressStore, TodoStore.
@MainActor
final class PipelineIntegrationService: ObservableObject {

    // MARK: - Published State

    @Published var currentJobId: String?
    @Published var jobState: JobState = .intake
    @Published var completedTasks: Int = 0
    @Published var totalTasks: Int = 0
    @Published var isRunning: Bool = false
    @Published var lastError: String?
    @Published var circuitBreakerActive: Bool = false

    // MARK: - Dependencies

    weak var chatStore: ChatStore?
    weak var taskActivityStore: TaskActivityStore?
    weak var swarmProgressStore: SwarmProgressStore?
    weak var todoStore: TodoStore?
    weak var executionController: ExecutionController?

    // MARK: - Internal State

    var activeStreamTask: Task<Void, Never>?
    var conversationId: UUID?
    var assistantMessageId: UUID?
    var planConversationId: UUID?
    var accumulatedText: [String: String] = [:]
    var onCompletion: ((PipelineCompletionContext) -> Void)?
    private var jobStartTime: Date?

    let facade: PipelineFacade

    var isPlanBuild: Bool {
        planConversationId != nil
    }

    // MARK: - Init

    init(facadeConfig: PipelineFacadeConfig = PipelineFacadeConfig()) {
        self.facade = PipelineFacade(config: facadeConfig)
    }

    // MARK: - Configuration

    func configure(
        chatStore: ChatStore,
        taskActivityStore: TaskActivityStore,
        swarmProgressStore: SwarmProgressStore,
        todoStore: TodoStore,
        executionController: ExecutionController
    ) {
        self.chatStore = chatStore
        self.taskActivityStore = taskActivityStore
        self.swarmProgressStore = swarmProgressStore
        self.todoStore = todoStore
        self.executionController = executionController
    }

    // MARK: - Execute Job

    func executeJob(
        _ job: PipelineJob,
        tasks: [TaskNode],
        workerAdapter: AgentWorkerAdapter,
        conversationId: UUID,
        assistantMessageId: UUID,
        planConversationId: UUID? = nil,
        onCompletion: ((PipelineCompletionContext) -> Void)? = nil
    ) {
        guard !isRunning else { return }

        self.conversationId = conversationId
        self.assistantMessageId = assistantMessageId
        self.planConversationId = planConversationId
        self.onCompletion = onCompletion
        self.accumulatedText.removeAll()
        self.lastError = nil
        self.circuitBreakerActive = false
        self.isRunning = true
        self.currentJobId = job.jobId
        self.jobStartTime = Date()

        let taskTitles = tasks.map(\.title)
        swarmProgressStore?.setSteps(taskTitles, conversationId: conversationId)

        chatStore?.beginTask(conversationId: conversationId)

        activeStreamTask = Task {
            let stream = await facade.executeJob(
                job, tasks: tasks, workerAdapter: workerAdapter
            )
            for await event in stream {
                guard !Task.isCancelled else { break }
                if executionController?.swarmStopRequested == true {
                    await facade.cancel()
                    break
                }
                await handleEvent(event)
            }
            finalizeExecution()
        }
    }

    // MARK: - Cancel

    func cancelCurrentJob() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        Task { await facade.cancel() }
        finalizeExecution()
    }

    // MARK: - Finalize

    func finalizeExecution() {
        let durationMs: Int
        if let start = jobStartTime {
            durationMs = Int(Date().timeIntervalSince(start) * 1000)
        } else {
            durationMs = 0
        }

        let ctx = PipelineCompletionContext(
            jobId: currentJobId ?? "",
            planConversationId: planConversationId,
            conversationId: conversationId ?? UUID(),
            completedTasks: completedTasks,
            totalTasks: totalTasks,
            durationMs: durationMs,
            success: lastError == nil
        )

        isRunning = false
        chatStore?.setLastAssistantStreaming(false, in: conversationId)
        chatStore?.endTask(conversationId: conversationId)
        activeStreamTask = nil

        onCompletion?(ctx)
        onCompletion = nil
        planConversationId = nil
        jobStartTime = nil
    }
}
