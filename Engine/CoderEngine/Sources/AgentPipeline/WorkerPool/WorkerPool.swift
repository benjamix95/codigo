import Foundation

// MARK: - WorkerTaskResult

/// Risultato di un task completato nel worker pool (§11.1).
public struct WorkerTaskResult: Sendable {
    public let taskId: String
    public let agentName: String
    public let agentRole: AgentRole
    public let success: Bool
    public let envelope: AgentActionEnvelope?
    public let error: String?
    public let durationMs: Int
    public let providerId: String?

    public init(
        taskId: String,
        agentName: String,
        agentRole: AgentRole,
        success: Bool,
        envelope: AgentActionEnvelope? = nil,
        error: String? = nil,
        durationMs: Int = 0,
        providerId: String? = nil
    ) {
        self.taskId = taskId
        self.agentName = agentName
        self.agentRole = agentRole
        self.success = success
        self.envelope = envelope
        self.error = error
        self.durationMs = durationMs
        self.providerId = providerId
    }
}

// MARK: - WorkerPoolError

public enum WorkerPoolError: Error, Sendable, Equatable {
    case poolShutdown
    case atCapacity
    case taskAlreadyRunning(taskId: String)
}

// MARK: - WorkerPoolDelegate

/// Delegate per notificare completamento task all'orchestrator.
public protocol WorkerPoolDelegate: AnyObject, Sendable {
    func workerPool(_ pool: WorkerPool, didComplete result: WorkerTaskResult) async
}

// MARK: - WorkerPool

/// Pool di worker con concurrency limit e dispatch asincrono (§11.1).
///
/// Regole:
/// - `activeWorkers` MUST MAI superare `maxWorkers`
/// - Worker rilascia slot al completamento (success o failure)
/// - Supporta backpressure tramite `BackpressureController`
public actor WorkerPool {

    private let baseMaxWorkers: Int
    private var isShutdown = false
    private var activeTasks: Set<String> = []
    private var runningWorkerTasks: [String: Task<Void, Never>] = [:]
    private var pendingResults: [WorkerTaskResult] = []
    private let backpressure: BackpressureController?
    private let taskTimeoutMs: UInt64 = 120_000

    public weak var delegate: WorkerPoolDelegate?

    // MARK: - Metrics

    private(set) var totalDispatched: Int = 0
    private(set) var totalCompleted: Int = 0
    private(set) var totalFailed: Int = 0

    public init(
        maxWorkers: Int = 4,
        backpressure: BackpressureController? = nil
    ) {
        self.baseMaxWorkers = min(max(1, maxWorkers), 12)
        self.backpressure = backpressure
    }

    // MARK: - Capacity

    /// Max worker effettivo, tenendo conto della backpressure.
    public var maxWorkers: Int {
        get async {
            guard let bp = backpressure else { return baseMaxWorkers }
            return await bp.effectiveMaxWorkers(base: baseMaxWorkers)
        }
    }

    /// Numero di worker attivi.
    public var activeCount: Int {
        activeTasks.count
    }

    /// True se il pool ha raggiunto la capacità massima.
    public var isAtCapacity: Bool {
        get async {
            let effective = await maxWorkers
            return activeTasks.count >= effective
        }
    }

    /// Slot disponibili.
    public var availableSlots: Int {
        get async {
            let effective = await maxWorkers
            return max(0, effective - activeTasks.count)
        }
    }

    // MARK: - Dispatch

    /// Dispatcher per esecuzione di un task agent.
    /// `work` è la closure asincrona che esegue il lavoro reale dell'agente.
    public func dispatch(
        taskId: String,
        agentName: String,
        agentRole: AgentRole,
        providerId: String? = nil,
        work: @escaping @Sendable () async -> WorkerTaskResult
    ) async throws {
        guard !isShutdown else {
            throw WorkerPoolError.poolShutdown
        }
        guard !activeTasks.contains(taskId) else {
            throw WorkerPoolError.taskAlreadyRunning(taskId: taskId)
        }

        let atCap = await isAtCapacity
        guard !atCap else {
            throw WorkerPoolError.atCapacity
        }

        activeTasks.insert(taskId)
        totalDispatched += 1

        let capturedTaskId = taskId
        let capturedAgentName = agentName
        let capturedAgentRole = agentRole
        let capturedProviderId = providerId
        let timeoutNs = taskTimeoutMs * 1_000_000

        let workerTask = Task { [weak self] in
            guard let self else {
                NSLog("[WorkerPool] self deallocated before task %@ could run", capturedTaskId)
                return
            }

            let result: WorkerTaskResult = await withTaskGroup(of: WorkerTaskResult.self) { group in
                group.addTask { await work() }
                group.addTask {
                    try? await Task.sleep(nanoseconds: timeoutNs)
                    return WorkerTaskResult(
                        taskId: capturedTaskId,
                        agentName: capturedAgentName,
                        agentRole: capturedAgentRole,
                        success: false,
                        error: "Worker task timed out after \(timeoutNs / 1_000_000)ms",
                        providerId: capturedProviderId
                    )
                }
                guard let first = await group.next() else {
                    return WorkerTaskResult(
                        taskId: capturedTaskId,
                        agentName: capturedAgentName,
                        agentRole: capturedAgentRole,
                        success: false,
                        error: "Worker task group unexpectedly empty",
                        providerId: capturedProviderId
                    )
                }
                group.cancelAll()
                return first
            }
            await self.handleCompletion(result)
        }
        runningWorkerTasks[taskId] = workerTask
    }

    // MARK: - Completion

    /// Raccoglie i risultati completati. Se vuoto, restituisce array vuoto.
    public func collectResults() -> [WorkerTaskResult] {
        let results = pendingResults
        pendingResults.removeAll()
        return results
    }

    // MARK: - Lifecycle

    public func shutdown() {
        isShutdown = true
        let workerTasks = runningWorkerTasks.values
        for task in workerTasks {
            task.cancel()
        }
    }

    public func shutdownAndWait(timeoutMs: Int = 5_000) async {
        shutdown()
        let tasks = Array(runningWorkerTasks.values)
        guard !tasks.isEmpty else { return }
        let timeoutNs = UInt64(timeoutMs) * 1_000_000
        await withTaskGroup(of: Void.self) { group in
            for task in tasks {
                group.addTask { await task.value }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNs)
            }
            await group.next()
            group.cancelAll()
        }
    }

    public func reset() {
        for task in runningWorkerTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
        runningWorkerTasks.removeAll()
        pendingResults.removeAll()
        totalDispatched = 0
        totalCompleted = 0
        totalFailed = 0
        isShutdown = false
    }

    // MARK: - Cancel All

    /// Cancella tutti i task in esecuzione e libera gli slot.
    public func cancelAll() {
        for (taskId, task) in runningWorkerTasks {
            NSLog("[WorkerPool] cancelAll: cancelling task %@", taskId)
            task.cancel()
        }
        activeTasks.removeAll()
        runningWorkerTasks.removeAll()
    }

    // MARK: - Private

    private func handleCompletion(_ result: WorkerTaskResult) async {
        activeTasks.remove(result.taskId)
        runningWorkerTasks.removeValue(forKey: result.taskId)
        pendingResults.append(result)

        if result.success {
            totalCompleted += 1
        } else {
            totalFailed += 1
        }

        if let delegate {
            await delegate.workerPool(self, didComplete: result)
        } else {
            NSLog("[WorkerPool] delegate deallocated, completion for task %@ only stored in pendingResults", result.taskId)
        }
    }
}
