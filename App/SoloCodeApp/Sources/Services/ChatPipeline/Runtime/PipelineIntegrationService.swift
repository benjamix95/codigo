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

    @Published private(set) var snapshotsByConversation: [UUID: PipelineConversationSnapshot] = [:]

    // MARK: - Dependencies

    private let dependencyBindings = PipelineIntegrationDependencyBindings()
    var chatStore: ChatStore? { dependencyBindings.resolvedChatStore() }
    var taskActivityStore: TaskActivityStore? { dependencyBindings.resolvedTaskActivityStore() }
    var swarmProgressStore: SwarmProgressStore? { dependencyBindings.resolvedSwarmProgressStore() }
    var todoStore: TodoStore? { dependencyBindings.resolvedTodoStore() }
    var executionController: ExecutionController? { dependencyBindings.resolvedExecutionController() }

    // MARK: - Internal State

    private var runtimesByConversation: [UUID: PipelineConversationRuntime] = [:]
    var debugStoresByConversation: [UUID: DebugProjectionStoreBinding] = [:]
    var pendingDebugEventsByConversation: [UUID: [NormalizedEvent]] = [:]
    var suppressedDebugProjectionConversationIds: Set<UUID> = []
    private let facadeConfig: PipelineFacadeConfig
    private var dirtySnapshotConversationIds: Set<UUID> = []
    private var snapshotFlushScheduled = false

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
        guard !isRunning(for: conversationId) else {
            // #region agent log
            AgentDebugSessionNDJSONLog.append(
                hypothesisId: "SEND",
                location: "PipelineIntegrationService.executeJob",
                message: "skipped_already_running",
                data: [
                    "conversationId": conversationId.uuidString,
                    "assistantMessageId": assistantMessageId.uuidString,
                ]
            )
            // #endregion
            return
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

    // MARK: - Queries

    func snapshot(for conversationId: UUID?) -> PipelineConversationSnapshot? {
        guard let conversationId else { return nil }
        return snapshotsByConversation[conversationId]
    }

    func isRunning(for conversationId: UUID?) -> Bool {
        snapshot(for: conversationId)?.isRunning == true
    }

    // MARK: - Teardown

    private func claimTeardownRuntime(for conversationId: UUID) -> PipelineConversationRuntime? {
        if let runtime = runtimesByConversation[conversationId], let chatStore {
            flushPendingRustBridgeEventsIfNeeded(
                conversationId: conversationId,
                runtime: runtime,
                chatStore: chatStore
            )
        }
        guard let runtime = runtimesByConversation[conversationId] else { return nil }
        guard runtime.beginTeardownIfNeeded() else { return nil }
        flushSnapshotNow(for: conversationId)
        return runtime
    }

    private func completionContext(
        for runtime: PipelineConversationRuntime,
        conversationId: UUID
    ) -> PipelineCompletionContext {
        let durationMs = Int(Date().timeIntervalSince(runtime.jobStartTime) * 1000)
        return PipelineCompletionContext(
            jobId: runtime.currentJobId,
            planConversationId: runtime.planConversationId,
            conversationId: conversationId,
            completedTasks: runtime.completedTasks,
            totalTasks: runtime.totalTasks,
            durationMs: durationMs,
            success: !runtime.wasCancelled && runtime.lastError == nil,
            wasCancelled: runtime.wasCancelled
        )
    }

    private func completeTeardown(
        _ runtime: PipelineConversationRuntime,
        for conversationId: UUID,
        completionContext: PipelineCompletionContext?
    ) {
        guard runtime.teardownState != .finished else { return }

        runtime.finishTeardown()
        chatStore?.setLastAssistantStreaming(false, in: conversationId)
        chatStore?.endTask(conversationId: conversationId)
        if let completionContext {
            runtime.onCompletion?(completionContext)
        }
        runtimesByConversation.removeValue(forKey: conversationId)
        snapshotsByConversation.removeValue(forKey: conversationId)
        swarmProgressStore?.clear(conversationId: conversationId)
        resolvePendingDebugEventsBeforeTeardown(for: conversationId)
        unregisterDebugStore(for: conversationId)
        suppressedDebugProjectionConversationIds.remove(conversationId)
        flushSnapshotNow(for: conversationId)
    }

    // MARK: - Runtime Helpers

    func runtime(for conversationId: UUID) -> PipelineConversationRuntime? {
        guard let runtime = runtimesByConversation[conversationId],
              runtime.teardownState == .running else {
            return nil
        }
        return runtime
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
        flushSnapshotNow(for: conversationId)
    }

    func persistSnapshot(for conversationId: UUID) {
        dirtySnapshotConversationIds.insert(conversationId)
        scheduleSnapshotFlush()
    }

    /// Forces immediate snapshot flush for a conversation (used during teardown).
    private func flushSnapshotNow(for conversationId: UUID) {
        dirtySnapshotConversationIds.remove(conversationId)
        if let runtime = runtimesByConversation[conversationId] {
            snapshotsByConversation[conversationId] = runtime.snapshot
        } else {
            snapshotsByConversation.removeValue(forKey: conversationId)
        }
    }

    private func scheduleSnapshotFlush() {
        guard !snapshotFlushScheduled else { return }
        snapshotFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.snapshotFlushScheduled = false
            let dirty = self.dirtySnapshotConversationIds
            self.dirtySnapshotConversationIds.removeAll()
            PipelineSnapshotFlushSignpost.measureBatch(dirtyCount: dirty.count) {
                for conversationId in dirty {
                    if let runtime = self.runtimesByConversation[conversationId] {
                        self.snapshotsByConversation[conversationId] = runtime.snapshot
                    } else {
                        self.snapshotsByConversation.removeValue(forKey: conversationId)
                    }
                }
            }
        }
    }
}
