import Combine
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
private final class PipelineIntegrationDependencyBindings {
    weak var chatStore: ChatStore?
    weak var taskActivityStore: TaskActivityStore?
    weak var swarmProgressStore: SwarmProgressStore?
    weak var todoStore: TodoStore?
    weak var executionController: ExecutionController?

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

    private func resolve<T>(
        _ value: T?,
        name: StaticString
    ) -> T? {
        guard let value else {
            NSLog("[PipelineIntegrationService] Missing dependency: %@", String(describing: name))
            return nil
        }
        return value
    }

    func resolvedChatStore() -> ChatStore? {
        resolve(chatStore, name: "ChatStore")
    }

    func resolvedTaskActivityStore() -> TaskActivityStore? {
        resolve(taskActivityStore, name: "TaskActivityStore")
    }

    func resolvedSwarmProgressStore() -> SwarmProgressStore? {
        resolve(swarmProgressStore, name: "SwarmProgressStore")
    }

    func resolvedTodoStore() -> TodoStore? {
        resolve(todoStore, name: "TodoStore")
    }

    func resolvedExecutionController() -> ExecutionController? {
        resolve(executionController, name: "ExecutionController")
    }
}

@MainActor
final class PipelineIntegrationService: ObservableObject {

    // MARK: - Published State

    var snapshotsByConversation: [UUID: PipelineConversationSnapshot] = [:]

    /// Incrementato quando cambia la coda degli eventi debug bufferizzati o lo stato suppress (per aggiornare il pannello).
    @Published private(set) var debugProjectionBufferRevision: UInt = 0

    // MARK: - Dependencies

    private let dependencyBindings = PipelineIntegrationDependencyBindings()
    var chatStore: ChatStore? { dependencyBindings.resolvedChatStore() }
    var taskActivityStore: TaskActivityStore? { dependencyBindings.resolvedTaskActivityStore() }
    var swarmProgressStore: SwarmProgressStore? { dependencyBindings.resolvedSwarmProgressStore() }
    var todoStore: TodoStore? { dependencyBindings.resolvedTodoStore() }
    var executionController: ExecutionController? { dependencyBindings.resolvedExecutionController() }

    // MARK: - Internal State

    var runtimesByConversation: [UUID: PipelineConversationRuntime] = [:]
    var debugStoresByConversation: [UUID: DebugProjectionStoreBinding] = [:]
    var pendingDebugEventsByConversation: [UUID: [NormalizedEvent]] = [:]
    var suppressedDebugProjectionConversationIds: Set<UUID> = []
    private let facadeConfig: PipelineFacadeConfig
    var dirtySnapshotConversationIds: Set<UUID> = []
    var snapshotFlushScheduled = false
    let snapshotDidChange = PassthroughSubject<UUID, Never>()

    // MARK: - Init

    init(facadeConfig: PipelineFacadeConfig = PipelineFacadeConfig()) {
        self.facadeConfig = facadeConfig
    }

    // MARK: - Configuration

    func bumpDebugProjectionBufferRevision() {
        debugProjectionBufferRevision &+= 1
    }

    func configure(
        chatStore: ChatStore,
        taskActivityStore: TaskActivityStore,
        swarmProgressStore: SwarmProgressStore,
        todoStore: TodoStore,
        executionController: ExecutionController
    ) {
        dependencyBindings.configure(
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            swarmProgressStore: swarmProgressStore,
            todoStore: todoStore,
            executionController: executionController
        )
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
        if isRunning(for: conversationId) {
            _ = discardConversationRuntime(for: conversationId)
        }

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
        flushSnapshotNow(for: conversationId)

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
                guard !Task.isCancelled else { break }
                self.handleEvent(event, for: conversationId)
            }
            self.finalizeExecution(for: conversationId)
        }
    }

    // MARK: - Cancel

    @discardableResult
    func cancelCurrentJob(for conversationId: UUID?) -> Bool {
        guard let conversationId,
              let runtime = claimTeardownRuntime(for: conversationId) else { return false }

        runtime.wasCancelled = true
        runtime.activeStreamTask?.cancel()
        runtime.activeStreamTask = nil

        let facade = runtime.facade
        let completionCtx = completionContext(for: runtime, conversationId: conversationId)
        // Teardown UI e registry subito: evita snapshot/task attivi finché await cancel() non ritorna.
        completeTeardown(runtime, for: conversationId, completionContext: completionCtx)

        Task { @MainActor in
            await facade.cancel()
        }
        return true
    }

    @discardableResult
    func discardConversationRuntime(for conversationId: UUID?) -> Bool {
        guard let conversationId else { return false }
        guard let runtime = claimTeardownRuntime(for: conversationId) else {
            snapshotsByConversation.removeValue(forKey: conversationId)
            resolvePendingDebugEventsBeforeTeardown(for: conversationId)
            unregisterDebugStore(for: conversationId)
            suppressedDebugProjectionConversationIds.remove(conversationId)
            flushSnapshotNow(for: conversationId)
            return false
        }

        runtime.wasCancelled = true
        runtime.activeStreamTask?.cancel()
        runtime.activeStreamTask = nil

        let facade = runtime.facade
        completeTeardown(runtime, for: conversationId, completionContext: nil)

        Task { @MainActor in
            await facade.cancel()
        }
        return true
    }

    // MARK: - Finalize

    func finalizeExecution(for conversationId: UUID) {
        guard let runtime = claimTeardownRuntime(for: conversationId) else { return }

        completeTeardown(
            runtime,
            for: conversationId,
            completionContext: completionContext(for: runtime, conversationId: conversationId)
        )
    }

}
