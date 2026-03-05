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
    private var pendingResults: [WorkerTaskResult] = []
    private let backpressure: BackpressureController?

    public weak var delegate: WorkerPoolDelegate?

    // MARK: - Metrics

    private(set) var totalDispatched: Int = 0
    private(set) var totalCompleted: Int = 0
    private(set) var totalFailed: Int = 0

    public init(
        maxWorkers: Int = 4,
        backpressure: BackpressureController? = nil
    ) {
        self.baseMaxWorkers = min(max(1, maxWorkers), 8)
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

        Task { [weak self] in
            let result = await work()
            await self?.handleCompletion(result)
        }
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
    }

    public func reset() {
        activeTasks.removeAll()
        pendingResults.removeAll()
        totalDispatched = 0
        totalCompleted = 0
        totalFailed = 0
        isShutdown = false
    }

    // MARK: - Private

    private func handleCompletion(_ result: WorkerTaskResult) async {
        activeTasks.remove(result.taskId)
        pendingResults.append(result)

        if result.success {
            totalCompleted += 1
        } else {
            totalFailed += 1
        }

        await delegate?.workerPool(self, didComplete: result)
    }
}
