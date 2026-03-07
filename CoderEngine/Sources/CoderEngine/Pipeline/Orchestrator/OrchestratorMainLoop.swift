import Foundation

// MARK: - OrchestratorConfig

/// Configurazione iniettabile per l'Orchestrator (§5.4).
public struct OrchestratorConfig: Sendable {
    public let tickIntervalMs: Int
    public let completionTimeoutMs: Int

    public init(
        tickIntervalMs: Int = 100,
        completionTimeoutMs: Int = 5000
    ) {
        self.tickIntervalMs = tickIntervalMs
        self.completionTimeoutMs = completionTimeoutMs
    }
}

// MARK: - OrchestratorMainLoop

/// Main loop dell'orchestrator pipeline (§5.4).
///
/// Coordina tutti i sotto-componenti:
/// - JobStateMachine: ciclo di vita job
/// - DagScheduler: ready tasks + ordinamento
/// - WorkerPool: dispatch + concurrency limit
/// - PipelineLockManager: file + symbol scope locks
/// - BackpressureController: segnali rallentamento
/// - SwarmBudgetManager: limiti agenti per ruolo
/// - AgentNameAssigner: naming convention
/// - EventBus: emissione eventi
/// - TaskCompletionHandler: routing risultati per ruolo
public actor OrchestratorMainLoop {

    // MARK: - Dependencies

    public let stateMachine: JobStateMachine
    public let scheduler: DagScheduler
    public let workerPool: WorkerPool
    public let lockManager: PipelineLockManager
    public let backpressure: BackpressureController
    public let swarmBudget: SwarmBudgetManager
    public let nameAssigner: AgentNameAssigner
    public let eventBus: EventBus
    public let completionHandler: TaskCompletionHandler
    public let roleStrategy: TaskRoleSelectionStrategy
    public let config: OrchestratorConfig
    public let workerAdapter: AgentWorkerAdapter?

    // MARK: - State

    private var isRunning = false
    private var consecutiveFailures: Int = 0
    private(set) var tickCount: UInt64 = 0

    public init(
        stateMachine: JobStateMachine,
        scheduler: DagScheduler,
        workerPool: WorkerPool,
        lockManager: PipelineLockManager,
        backpressure: BackpressureController,
        swarmBudget: SwarmBudgetManager,
        nameAssigner: AgentNameAssigner,
        eventBus: EventBus,
        completionHandler: TaskCompletionHandler = TaskCompletionHandler(),
        roleStrategy: TaskRoleSelectionStrategy = TaskRoleSelectionStrategy(),
        config: OrchestratorConfig = OrchestratorConfig(),
        workerAdapter: AgentWorkerAdapter? = nil
    ) {
        self.stateMachine = stateMachine
        self.scheduler = scheduler
        self.workerPool = workerPool
        self.lockManager = lockManager
        self.backpressure = backpressure
        self.swarmBudget = swarmBudget
        self.nameAssigner = nameAssigner
        self.eventBus = eventBus
        self.completionHandler = completionHandler
        self.roleStrategy = roleStrategy
        self.config = config
        self.workerAdapter = workerAdapter
    }

    // MARK: - Run

    /// Esegue un singolo tick del main loop (§5.4).
    /// Restituisce `true` se il job è ancora in corso, `false` se terminato.
    ///
    /// Fasi del tick:
    /// 1. Guard timeout job
    /// 2. Guard circuit breaker
    /// 3. Backpressure check
    /// 4. Scheduling ready tasks
    /// 5. Collect risultati completati
    /// 6. Handle completamento per ruolo
    public func tick() async -> Bool {
        let job = await stateMachine.job
        let currentState = await stateMachine.currentState

        guard !currentState.isTerminal else {
            return false
        }
        if Task.isCancelled {
            try? await stateMachine.abort(reason: "Pipeline task cancelled")
            return false
        }

        tickCount += 1

        // 1. Guard timeout (§5.4)
        let elapsed = Date().timeIntervalSince(job.createdAt) * 1000
        if Int(elapsed) > job.jobTimeoutMs {
            await emitEvent(
                type: .jobTimeout,
                jobId: job.jobId,
                payload: ["elapsed_ms": "\(Int(elapsed))"]
            )
            try? await stateMachine.abort(reason: "Job timeout exceeded")
            return false
        }

        // 2. Backpressure check
        let shouldPause = await backpressure.shouldPauseScheduling
        if !shouldPause {
            await scheduleReadyTasks(job: job)
        }

        // 3. Collect risultati
        let results = await workerPool.collectResults()
        for result in results {
            await handleResult(result, job: job)
        }

        // 4. Check tutti i task terminali
        let allDone = await scheduler.allTasksTerminal
        if allDone {
            let failedCount = await scheduler.countByStatus(.failed)
            if failedCount == 0 {
                await advanceToFinalized()
            } else {
                _ = try? await stateMachine.transition(to: .failed, reason: "\(failedCount) tasks failed")
                _ = try? await stateMachine.transition(to: .aborted, reason: "Job failed with errors")
            }
            return false
        }

        return true
    }

    /// Loop completo: esegue tick fino a terminazione del job.
    public func run() async {
        isRunning = true

        await advanceToExecution()

        while isRunning {
            if Task.isCancelled {
                try? await stateMachine.abort(reason: "Pipeline task cancelled")
                break
            }
            let shouldContinue = await tick()
            guard shouldContinue else { break }

            let sleepNs = UInt64(config.tickIntervalMs) * 1_000_000
            try? await Task.sleep(nanoseconds: sleepNs)
        }

        isRunning = false
    }

    /// Avanza la state machine attraverso gli stati pre-esecuzione:
    /// intake -> planning -> contextReady -> scheduled -> executing.
    private func advanceToExecution() async {
        let targets: [JobState] = [
            .planning, .contextReady, .scheduled, .executing
        ]
        for target in targets {
            let current = await stateMachine.currentState
            guard !current.isTerminal, current.canTransition(to: target) else { break }
            _ = try? await stateMachine.transition(
                to: target,
                reason: "Pipeline bootstrap"
            )
        }
    }

    /// Avanza la state machine attraverso gli stati post-esecuzione:
    /// executing -> reviewing -> validating -> applying -> verifying -> finalized.
    private func advanceToFinalized() async {
        let targets: [JobState] = [
            .reviewing, .validating, .applying, .verifying, .finalized
        ]
        for target in targets {
            let current = await stateMachine.currentState
            guard !current.isTerminal, current.canTransition(to: target) else { break }
            _ = try? await stateMachine.transition(
                to: target,
                reason: "All tasks completed"
            )
        }
    }

    /// Ferma il loop.
    public func stop() {
        isRunning = false
    }

    // MARK: - Scheduling

    private func scheduleReadyTasks(job: PipelineJob) async {
        let readyTasks = await scheduler.getReadyTasks()

        for task in readyTasks {
            let atCapacity = await workerPool.isAtCapacity
            if atCapacity {
                await backpressure.activate(.workerQueueFull)
                await emitEvent(
                    type: .schedulerBackpressure,
                    jobId: job.jobId,
                    taskId: task.taskId
                )
                break
            }

            let role = nextAgentRole(for: task, job: job)

            let hasCapacity = await swarmBudget.hasCapacity(
                task: task,
                role: role
            )
            guard hasCapacity else { continue }

            let scope = LockScope(from: task)
            let lockAcquired = await lockManager.acquire(
                scope: scope,
                taskId: task.taskId
            )
            guard lockAcquired else {
                await scheduler.markWaiting(task.taskId)
                continue
            }

            await emitEvent(
                type: .lockAcquired,
                jobId: job.jobId,
                taskId: task.taskId
            )

            let agentName = await nameAssigner.assign(task: task, role: role)

            await scheduler.setPreferredAgentRole(task.taskId, role: nil)
            await scheduler.updateTaskStatus(task.taskId, status: .running)
            _ = await swarmBudget.reserve(task: task, role: role)

            let taskId = task.taskId
            let jobId = job.jobId

            let work: @Sendable () async -> WorkerTaskResult
            if let adapter = workerAdapter {
                work = await adapter.makeWorkClosure(
                    task: task, agentName: agentName, role: role
                )
            } else {
                work = Self.stubClosure(
                    taskId: taskId, agentName: agentName, role: role
                )
            }

            do {
                try await workerPool.dispatch(
                    taskId: taskId,
                    agentName: agentName,
                    agentRole: role,
                    work: work
                )
            } catch {
                await scheduler.updateTaskStatus(taskId, status: .pending)
                await swarmBudget.release(task: task, role: role)
                await lockManager.release(taskId: taskId)

                await emitEvent(
                    type: .lockReleased,
                    jobId: jobId,
                    taskId: taskId
                )
                continue
            }

            await emitEvent(
                type: .taskStarted,
                jobId: jobId,
                taskId: taskId,
                payload: ["agent_name": agentName, "role": role.rawValue]
            )
        }

        let isAtCap = await workerPool.isAtCapacity
        if !isAtCap {
            await backpressure.deactivate(.workerQueueFull)
        }
    }

    // MARK: - Result Handling

    private func handleResult(_ result: WorkerTaskResult, job: PipelineJob) async {
        await swarmBudget.release(
            task: TaskNode(taskId: result.taskId, title: ""),
            role: result.agentRole
        )
        await lockManager.release(taskId: result.taskId)

        await emitEvent(
            type: .lockReleased,
            jobId: job.jobId,
            taskId: result.taskId
        )

        if result.success {
            consecutiveFailures = 0
            await handleSuccessResult(result, job: job)
        } else {
            consecutiveFailures += 1
            await handleFailureResult(result, job: job)
        }
    }

    private func handleSuccessResult(
        _ result: WorkerTaskResult,
        job: PipelineJob
    ) async {
        await emitEvent(
            type: .taskCompleted,
            jobId: job.jobId,
            taskId: result.taskId,
            payload: [
                "agent_name": result.agentName,
                "duration_ms": "\(result.durationMs)",
                "role": result.agentRole.rawValue
            ]
        )

        if result.agentRole == .explorer {
            await scheduler.markContextEnriched(result.taskId)
        }

        let task = await scheduler.task(byId: result.taskId) ??
            TaskNode(taskId: result.taskId, title: "")

        let completionData = Self.extractCompletionData(from: result)

        let action = completionHandler.handleSuccess(
            result: result,
            task: task,
            hasCriticalFindings: completionData.hasCriticalFindings,
            testsPass: completionData.testsPass,
            shouldInvokeDocWriter: completionData.shouldInvokeDocWriter
        )

        await applyAction(action, job: job)
    }

    private func handleFailureResult(
        _ result: WorkerTaskResult,
        job: PipelineJob
    ) async {
        await emitEvent(
            type: .taskFailed,
            jobId: job.jobId,
            taskId: result.taskId,
            payload: ["error": result.error ?? "unknown"]
        )

        let task = await scheduler.task(byId: result.taskId) ??
            TaskNode(taskId: result.taskId, title: "")

        let totalTasks = await scheduler.taskCount
        let failedCount = await scheduler.countByStatus(.failed)

        let action = completionHandler.handleFailure(
            result: result,
            task: task,
            consecutiveFailures: consecutiveFailures,
            errorBudget: job.errorBudget,
            totalTasks: totalTasks,
            failedTaskCount: failedCount
        )

        await applyAction(action, job: job)
    }

    // MARK: - Apply Action

    private func applyAction(_ action: CompletionAction, job: PipelineJob) async {
        switch action {
        case .scheduleNextAgent(let taskId, let role):
            await scheduler.setPreferredAgentRole(taskId, role: role)
            await scheduler.updateTaskStatus(taskId, status: .pending)

        case .scheduleFixRound(let taskId, _):
            await scheduler.setPreferredAgentRole(taskId, role: nil)
            await scheduler.scheduleRetry(taskId)

        case .transitionToValidation(let taskId):
            await scheduler.setPreferredAgentRole(taskId, role: nil)
            await scheduler.updateTaskStatus(taskId, status: .completed)

        case .blockTask(let taskId, _):
            await scheduler.setPreferredAgentRole(taskId, role: nil)
            await scheduler.updateTaskStatus(taskId, status: .blocked)

        case .retryTask(let taskId, _):
            await scheduler.setPreferredAgentRole(taskId, role: nil)
            await scheduler.scheduleRetry(taskId)

        case .failTask(let taskId, _):
            await scheduler.setPreferredAgentRole(taskId, role: nil)
            await scheduler.updateTaskStatus(taskId, status: .failed)

        case .abortJob(let reason):
            try? await stateMachine.abort(reason: reason)

        case .continueNormally:
            break
        }
    }

    // MARK: - Events

    private func emitEvent(
        type: PipelineEventType,
        jobId: String,
        taskId: String? = nil,
        payload: [String: String] = [:]
    ) async {
        let event = EventBusEvent(
            eventId: "evt_\(tickCount)_\(type.rawValue)",
            jobId: jobId,
            taskId: taskId,
            type: type,
            payload: payload,
            idempotencyKey: "\(jobId)_\(type.rawValue)_\(tickCount)_\(taskId ?? "none")"
        )
        try? await eventBus.publish(event)
    }

    // MARK: - Helpers

    // MARK: - Completion Data Extraction

    private struct CompletionData {
        let hasCriticalFindings: Bool
        let testsPass: Bool
        let shouldInvokeDocWriter: Bool
    }

    private static func extractCompletionData(
        from result: WorkerTaskResult
    ) -> CompletionData {
        guard let envelope = result.envelope else {
            return CompletionData(
                hasCriticalFindings: false,
                testsPass: true,
                shouldInvokeDocWriter: false
            )
        }

        let summaries = envelope.actions.compactMap(\.summary).joined(separator: " ").lowercased()

        let hasCritical = summaries.contains("critical")
            || summaries.contains("security vulnerability")
            || summaries.contains("blocking issue")

        let testsFail = summaries.contains("tests fail")
            || summaries.contains("test failure")
            || summaries.contains("build error")

        let needsDoc = envelope.actions.contains { $0.type == .docUpdate || $0.type == .docFlowUpdate }
            || summaries.contains("documentation needed")
            || summaries.contains("doc update")

        return CompletionData(
            hasCriticalFindings: hasCritical,
            testsPass: !testsFail,
            shouldInvokeDocWriter: needsDoc
        )
    }

    /// Determina il prossimo ruolo agente per un task (basato sul flusso §5.5).
    private func nextAgentRole(
        for task: TaskNode,
        job: PipelineJob
    ) -> AgentRole {
        roleStrategy.nextRole(for: task, job: job)
    }

    /// Stub di fallback usato nei test quando nessun adapter e' iniettato.
    private static func stubClosure(
        taskId: String,
        agentName: String,
        role: AgentRole
    ) -> @Sendable () async -> WorkerTaskResult {
        { WorkerTaskResult(
            taskId: taskId,
            agentName: agentName,
            agentRole: role,
            success: true,
            durationMs: 0
        ) }
    }
}
