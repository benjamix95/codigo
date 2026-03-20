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
    var consecutiveFailures: Int = 0
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
            let blockedCount = await scheduler.countByStatus(.blocked)
            if failedCount == 0 && blockedCount == 0 {
                await advanceToFinalized()
            } else {
                let reason: String
                if blockedCount > 0 {
                    reason = "\(blockedCount) tasks blocked"
                } else {
                    reason = "\(failedCount) tasks failed"
                }
                _ = try? await stateMachine.transition(to: .failed, reason: reason)
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

    /// Avanza la state machine attraverso gli stati pre-esecuzione.
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

    /// Avanza la state machine attraverso gli stati post-esecuzione.
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
}
