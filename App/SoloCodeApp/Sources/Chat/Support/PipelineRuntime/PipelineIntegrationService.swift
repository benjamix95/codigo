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
    let wasCancelled: Bool
}

// MARK: - PipelineIntegrationService

/// Service che collega la pipeline al layer UI di CoderIDE.
/// Consuma `PipelineUIEvent` e aggiorna ChatStore, TaskActivityStore,
/// SwarmProgressStore, TodoStore.
@MainActor
final class PipelineIntegrationService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var snapshotsByConversation: [UUID: PipelineConversationSnapshot] = [:]

    // MARK: - Dependencies

    weak var chatStore: ChatStore?
    weak var taskActivityStore: TaskActivityStore?
    weak var swarmProgressStore: SwarmProgressStore?
    weak var todoStore: TodoStore?
    weak var executionController: ExecutionController?

    // MARK: - Internal State

    private var runtimesByConversation: [UUID: PipelineConversationRuntime] = [:]
    var debugStoresByConversation: [UUID: DebugProjectionStoreBinding] = [:]
    var pendingDebugEventsByConversation: [UUID: [NormalizedEvent]] = [:]
    var suppressedDebugProjectionConversationIds: Set<UUID> = []
    private let facadeConfig: PipelineFacadeConfig

    // MARK: - Init

    init(facadeConfig: PipelineFacadeConfig = PipelineFacadeConfig()) {
        self.facadeConfig = facadeConfig
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
        providerId: String,
        conversationId: UUID,
        assistantMessageId: UUID,
        planConversationId: UUID? = nil,
        onCompletion: ((PipelineCompletionContext) -> Void)? = nil,
        rawEventHandler: ((_ type: String, _ payload: [String: String], _ providerId: String, _ conversationId: UUID?) -> Void)? = nil
    ) {
        guard !isRunning(for: conversationId) else { return }

        executionController?.clearSwarmStopRequested()

        let runtime = PipelineConversationRuntime(
            conversationId: conversationId,
            facade: PipelineFacade(config: facadeConfig),
            jobId: job.jobId,
            providerId: providerId,
            assistantMessageId: assistantMessageId,
            planConversationId: planConversationId,
            onCompletion: onCompletion,
            rawEventHandler: rawEventHandler
        )
        runtime.chatTurnState.orderedTextStreamIds = tasks.map(\.taskId)
        runtimesByConversation[conversationId] = runtime
        persistSnapshot(for: conversationId)

        let taskTitles = tasks.map(\.title)
        swarmProgressStore?.setSteps(taskTitles, conversationId: conversationId)

        chatStore?.beginTask(conversationId: conversationId)

        let facade = runtime.facade
        runtime.activeStreamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = await facade.executeJob(
                job, tasks: tasks, workerAdapter: workerAdapter
            )
            for await event in stream {
                guard !Task.isCancelled else { break }
                if executionController?.swarmStopRequested == true {
                    self.cancelCurrentJob(for: conversationId)
                    break
                }
                self.handleEvent(event, for: conversationId)
            }
            self.finalizeExecution(for: conversationId)
        }
    }

    // MARK: - Cancel

    @discardableResult
    func cancelCurrentJob(for conversationId: UUID?) -> Bool {
        guard let conversationId,
              let runtime = runtimesByConversation[conversationId] else { return false }

        runtime.wasCancelled = true
        runtime.activeStreamTask?.cancel()
        runtime.activeStreamTask = nil

        Task { @MainActor in
            await runtime.facade.cancel()
            self.finalizeExecution(for: conversationId)
        }
        return true
    }

    @discardableResult
    func discardConversationRuntime(for conversationId: UUID?) -> Bool {
        guard let conversationId else { return false }
        guard let runtime = runtimesByConversation.removeValue(forKey: conversationId) else {
            snapshotsByConversation.removeValue(forKey: conversationId)
            return false
        }

        runtime.wasCancelled = true
        runtime.activeStreamTask?.cancel()
        runtime.activeStreamTask = nil
        snapshotsByConversation.removeValue(forKey: conversationId)
        swarmProgressStore?.clear(conversationId: conversationId)
        chatStore?.endTask(conversationId: conversationId)
        unregisterDebugStore(for: conversationId)
        pendingDebugEventsByConversation.removeValue(forKey: conversationId)
        suppressedDebugProjectionConversationIds.remove(conversationId)

        Task { @MainActor in
            await runtime.facade.cancel()
        }
        return true
    }

    // MARK: - Finalize

    func finalizeExecution(for conversationId: UUID) {
        guard let runtime = runtimesByConversation[conversationId] else { return }

        runtime.isRunning = false
        let durationMs = Int(Date().timeIntervalSince(runtime.jobStartTime) * 1000)

        let ctx = PipelineCompletionContext(
            jobId: runtime.currentJobId,
            planConversationId: runtime.planConversationId,
            conversationId: conversationId,
            completedTasks: runtime.completedTasks,
            totalTasks: runtime.totalTasks,
            durationMs: durationMs,
            success: !runtime.wasCancelled && runtime.lastError == nil,
            wasCancelled: runtime.wasCancelled
        )

        chatStore?.setLastAssistantStreaming(false, in: conversationId)
        chatStore?.endTask(conversationId: conversationId)
        runtime.activeStreamTask = nil

        runtime.onCompletion?(ctx)
        runtimesByConversation.removeValue(forKey: conversationId)
        persistSnapshot(for: conversationId)
    }

    // MARK: - Queries

    func snapshot(for conversationId: UUID?) -> PipelineConversationSnapshot? {
        guard let conversationId else { return nil }
        return snapshotsByConversation[conversationId]
    }

    func isRunning(for conversationId: UUID?) -> Bool {
        snapshot(for: conversationId)?.isRunning == true
    }

    // MARK: - Runtime Helpers

    func runtime(for conversationId: UUID) -> PipelineConversationRuntime? {
        runtimesByConversation[conversationId]
    }

    func providerId(for conversationId: UUID?) -> String? {
        guard let conversationId else { return nil }
        return runtimesByConversation[conversationId]?.providerId
            ?? snapshotsByConversation[conversationId]?.providerId
    }

    func retargetAssistantMessage(
        for conversationId: UUID,
        assistantMessageId: UUID,
        turnId: String
    ) {
        guard let runtime = runtimesByConversation[conversationId] else { return }
        runtime.retargetAssistantMessage(
            assistantMessageId: assistantMessageId,
            turnId: turnId
        )
        persistSnapshot(for: conversationId)
    }

    func persistSnapshot(for conversationId: UUID) {
        if let runtime = runtimesByConversation[conversationId] {
            snapshotsByConversation[conversationId] = runtime.snapshot
        } else {
            snapshotsByConversation.removeValue(forKey: conversationId)
        }
    }
}
