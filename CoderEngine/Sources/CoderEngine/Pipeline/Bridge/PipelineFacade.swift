import Foundation

// MARK: - PipelineFacadeError

public enum PipelineFacadeError: Error, Sendable {
    case alreadyRunning
    case jobValidationFailed(String)
    case cancelled
}

// MARK: - PipelineFacadeConfig

public struct PipelineFacadeConfig: Sendable {
    public let tickIntervalMs: Int
    public let completionTimeoutMs: Int
    public let maxDeliveryAttempts: Int
    public let dlqCapacity: Int

    public init(
        tickIntervalMs: Int = 100,
        completionTimeoutMs: Int = 5000,
        maxDeliveryAttempts: Int = 3,
        dlqCapacity: Int = 1000
    ) {
        self.tickIntervalMs = tickIntervalMs
        self.completionTimeoutMs = completionTimeoutMs
        self.maxDeliveryAttempts = maxDeliveryAttempts
        self.dlqCapacity = dlqCapacity
    }
}

// MARK: - PipelineFacade

/// Entry point pubblico per eseguire job della pipeline.
/// Costruisce internamente tutti i sotto-componenti, sottoscrive l'EventBus
/// e mappa gli `EventBusEvent` in `PipelineUIEvent` per il layer UI.
public actor PipelineFacade {

    private let config: PipelineFacadeConfig
    private var runningJobId: String?

    public init(config: PipelineFacadeConfig = PipelineFacadeConfig()) {
        self.config = config
    }

    // MARK: - Execute

    /// Esegue un job e restituisce uno stream di eventi UI.
    /// Il DAG deve essere gia' popolato nel `DagScheduler` fornito,
    /// oppure passato come array di TaskNode tramite la factory.
    public func executeJob(
        _ job: PipelineJob,
        tasks: [TaskNode],
        workerAdapter: AgentWorkerAdapter
    ) -> AsyncStream<PipelineUIEvent> {
        let jobId = job.jobId
        let facadeConfig = config

        return AsyncStream { continuation in
            let task = Task {
                do {
                    try await self.guardNotRunning(jobId: jobId)
                    try job.validate()
                    for t in tasks { try t.validate() }
                } catch {
                    let reason = (error as? PipelineValidationError)
                        .map(\.localizedDescription) ?? error.localizedDescription
                    continuation.yield(.jobFailed(JobFailedPayload(
                        jobId: jobId, reason: reason, failedTasks: 0
                    )))
                    continuation.finish()
                    return
                }

                let components = await self.buildComponents(
                    job: job,
                    tasks: tasks,
                    facadeConfig: facadeConfig,
                    workerAdapter: workerAdapter
                )

                await self.subscribeUIBridge(
                    eventBus: components.eventBus,
                    jobId: jobId,
                    scheduler: components.scheduler,
                    stateMachine: components.stateMachine,
                    continuation: continuation
                )

                continuation.yield(.jobStarted(JobStartedPayload(
                    jobId: jobId, mode: job.mode, taskCount: tasks.count
                )))

                let startedAt = Date()
                await components.orchestrator.run()

                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                let finalState = await components.stateMachine.currentState
                let completedCount = await components.scheduler.countByStatus(.completed)
                let failedCount = await components.scheduler.countByStatus(.failed)

                if finalState == .finalized {
                    continuation.yield(.jobCompleted(JobCompletedPayload(
                        jobId: jobId, durationMs: durationMs,
                        completedTasks: completedCount, totalTasks: tasks.count
                    )))
                } else {
                    let reason = await components.stateMachine.history.last?.reason
                        ?? "Job ended in state: \(finalState.rawValue)"
                    continuation.yield(.jobFailed(JobFailedPayload(
                        jobId: jobId, reason: reason, failedTasks: failedCount
                    )))
                }

                await components.eventBus.shutdown()
                await self.clearRunning(jobId: jobId)
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Cancel

    public func cancel() {
        runningJobId = nil
    }

    // MARK: - Guard

    private func guardNotRunning(jobId: String) throws {
        guard runningJobId == nil else {
            throw PipelineFacadeError.alreadyRunning
        }
        runningJobId = jobId
    }

    private func clearRunning(jobId: String) {
        if runningJobId == jobId { runningJobId = nil }
    }

    // MARK: - Component Assembly

    private func buildComponents(
        job: PipelineJob,
        tasks: [TaskNode],
        facadeConfig: PipelineFacadeConfig,
        workerAdapter: AgentWorkerAdapter
    ) async -> PipelineComponents {
        let eventBus = EventBus(
            maxDeliveryAttempts: facadeConfig.maxDeliveryAttempts,
            dlqCapacity: facadeConfig.dlqCapacity
        )
        let stateMachine = JobStateMachine(job: job)
        let scheduler = DagScheduler()
        for t in tasks { try? await scheduler.addTask(t) }

        let backpressure = BackpressureController()
        let swarmBudget = SwarmBudgetManager(
            config: job.swarmBudget ?? SwarmBudgetConfig()
        )
        let nameAssigner = AgentNameAssigner()
        let lockManager = PipelineLockManager()

        let workerPool = WorkerPool(
            maxWorkers: job.maxConcurrentWorkers,
            backpressure: backpressure
        )

        let completionHandler = TaskCompletionHandler()
        let orchestratorConfig = OrchestratorConfig(
            tickIntervalMs: facadeConfig.tickIntervalMs,
            completionTimeoutMs: facadeConfig.completionTimeoutMs
        )

        let eventBridge = AgentWorkerEventBridge(
            eventBus: eventBus, jobId: job.jobId
        )
        await workerAdapter.setDelegate(eventBridge)

        let orchestrator = OrchestratorMainLoop(
            stateMachine: stateMachine,
            scheduler: scheduler,
            workerPool: workerPool,
            lockManager: lockManager,
            backpressure: backpressure,
            swarmBudget: swarmBudget,
            nameAssigner: nameAssigner,
            eventBus: eventBus,
            completionHandler: completionHandler,
            config: orchestratorConfig,
            workerAdapter: workerAdapter
        )

        return PipelineComponents(
            orchestrator: orchestrator,
            stateMachine: stateMachine,
            scheduler: scheduler,
            workerPool: workerPool,
            eventBus: eventBus,
            backpressure: backpressure
        )
    }

    // MARK: - Event Bridge

    private func subscribeUIBridge(
        eventBus: EventBus,
        jobId: String,
        scheduler: DagScheduler,
        stateMachine: JobStateMachine,
        continuation: AsyncStream<PipelineUIEvent>.Continuation
    ) async {
        let sub = EventSubscription(
            id: "ui_bridge_\(jobId)",
            filter: EventSubscriptionFilter(jobId: jobId)
        ) { event in
            let mapped = await Self.mapEventToUI(
                event: event,
                jobId: jobId,
                scheduler: scheduler,
                stateMachine: stateMachine
            )
            for uiEvent in mapped {
                continuation.yield(uiEvent)
            }
        }
        await eventBus.subscribe(sub)
    }

    private static func mapEventToUI(
        event: EventBusEvent,
        jobId: String,
        scheduler: DagScheduler,
        stateMachine: JobStateMachine
    ) async -> [PipelineUIEvent] {
        var results: [PipelineUIEvent] = []

        switch event.type {
        case .taskStarted:
            if let taskId = event.taskId {
                let title = await scheduler.task(byId: taskId)?.title ?? ""
                let agentName = event.payload["agent_name"] ?? "unknown"
                let roleName = event.payload["role"] ?? "coder"
                let role = AgentRole(rawValue: roleName) ?? .coder
                results.append(.taskStarted(TaskStartedPayload(
                    jobId: jobId, taskId: taskId, title: title,
                    agentName: agentName, role: role
                )))
            }

        case .taskCompleted:
            if let taskId = event.taskId {
                let agentName = event.payload["agent_name"] ?? ""
                let durationMs = Int(event.payload["duration_ms"] ?? "0") ?? 0
                results.append(.taskCompleted(TaskCompletedPayload(
                    jobId: jobId, taskId: taskId,
                    agentName: agentName, durationMs: durationMs
                )))
                let completed = await scheduler.countByStatus(.completed)
                let total = await scheduler.taskCount
                let state = await stateMachine.currentState
                results.append(.progressUpdate(ProgressPayload(
                    jobId: jobId, completedTasks: completed,
                    totalTasks: total, currentState: state
                )))
            }

        case .taskFailed:
            if let taskId = event.taskId {
                let error = event.payload["error"] ?? "unknown error"
                results.append(.taskFailed(TaskFailedPayload(
                    jobId: jobId, taskId: taskId, error: error
                )))
            }

        case .rollbackStarted:
            if let taskId = event.taskId {
                let reason = event.payload["reason"] ?? "rollback triggered"
                results.append(.rollbackTriggered(RollbackPayload(
                    jobId: jobId, taskId: taskId, reason: reason
                )))
            }

        case .circuitBreakerTriggered:
            let reason = event.payload["reason"] ?? ""
            results.append(.circuitBreakerTriggered(CircuitBreakerPayload(
                jobId: jobId, phase: .open, reason: reason
            )))

        case .schedulerBackpressure:
            results.append(.backpressureChanged(BackpressurePayload(
                jobId: jobId, active: true, activeWorkers: 0, maxWorkers: 0
            )))

        case .providerHealthChanged:
            let providerId = event.payload["provider_id"] ?? ""
            let statusRaw = event.payload["status"] ?? "healthy"
            let status = ProviderHealthStatus(rawValue: statusRaw) ?? .healthy
            results.append(.providerHealthChanged(ProviderHealthPayload(
                jobId: jobId, providerId: providerId, status: status
            )))

        case .errorBudgetLow:
            let failedPct = Int(event.payload["failed_percent"] ?? "0") ?? 0
            let maxPct = Int(event.payload["max_percent"] ?? "30") ?? 30
            let consecutive = Int(event.payload["consecutive"] ?? "0") ?? 0
            results.append(.errorBudgetLow(ErrorBudgetPayload(
                jobId: jobId, failedPercent: failedPct,
                maxPercent: maxPct, consecutiveFailures: consecutive
            )))

        case .textDelta:
            let delta = event.payload["delta"] ?? ""
            let taskId = event.taskId ?? event.payload["task_id"] ?? ""
            results.append(.textDelta(TextDeltaPayload(
                jobId: jobId, taskId: taskId, delta: delta
            )))

        case .textReplace:
            let replacement = event.payload["replacement"] ?? ""
            let taskId = event.taskId ?? event.payload["task_id"] ?? ""
            results.append(.textReplace(TextReplacePayload(
                jobId: jobId, taskId: taskId, replacement: replacement
            )))

        case .rawAgentEvent:
            break

        default:
            break
        }

        return results
    }
}

// MARK: - PipelineComponents

private struct PipelineComponents {
    let orchestrator: OrchestratorMainLoop
    let stateMachine: JobStateMachine
    let scheduler: DagScheduler
    let workerPool: WorkerPool
    let eventBus: EventBus
    let backpressure: BackpressureController
}
