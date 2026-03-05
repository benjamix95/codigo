import CoderEngine
import Foundation
import SwiftUI

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
    var accumulatedText: [String: String] = [:]

    let facade: PipelineFacade

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
        assistantMessageId: UUID
    ) {
        guard !isRunning else { return }

        self.conversationId = conversationId
        self.assistantMessageId = assistantMessageId
        self.accumulatedText.removeAll()
        self.lastError = nil
        self.circuitBreakerActive = false
        self.isRunning = true
        self.currentJobId = job.jobId

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
        isRunning = false
        chatStore?.setLastAssistantStreaming(false, in: conversationId)
        chatStore?.endTask(conversationId: conversationId)
        activeStreamTask = nil
    }
}
