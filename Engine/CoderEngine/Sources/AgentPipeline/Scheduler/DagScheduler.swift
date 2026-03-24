import Foundation

// MARK: - DagSchedulerError

public enum DagSchedulerError: Error, Sendable, Equatable {
    case duplicateTaskId(String)
    case dependencyNotFound(taskId: String, missingDep: String)
    case cyclicDependency(involved: [String])
}

// MARK: - DagScheduler

/// Scheduler DAG deterministico per task pipeline (§11.2).
///
/// Responsabilità:
/// - Gestione grafo DAG di TaskNode
/// - Estrazione ready tasks (dipendenze soddisfatte)
/// - Ordinamento per effective_priority (§8.4)
/// - Starvation prevention tramite wait_time_factor
/// - Validazione aciclicità
public actor DagScheduler {

    private var tasks: [String: TaskNode] = [:]
    private var dependentsByTask: [String: Set<String>] = [:]
    private var readyTaskIDs: Set<String> = []
    private var statusCounts: [TaskStatus: Int] = [:]
    private let priorityCalculator: PriorityCalculator
    private let maxRetryTimeoutMs: Int = 60_000
    private let maxRetryCount: Int = 3
    private var retryCountByTask: [String: Int] = [:]

    public init(priorityCalculator: PriorityCalculator = PriorityCalculator()) {
        self.priorityCalculator = priorityCalculator
    }

    // MARK: - Task Management

    /// Aggiunge task al DAG. Lancia errore se ID duplicato.
    public func addTask(_ task: TaskNode) throws {
        guard tasks[task.taskId] == nil else {
            throw DagSchedulerError.duplicateTaskId(task.taskId)
        }
        tasks[task.taskId] = task
        dependentsByTask[task.taskId, default: []] = dependentsByTask[task.taskId, default: []]
        for dependency in task.dependsOn {
            dependentsByTask[dependency, default: []].insert(task.taskId)
        }
        adjustStatusCounts(from: nil, to: task.status)
        refreshReadyState(for: task.taskId)
        refreshDependents(of: task.taskId)
    }

    /// Aggiunge un batch di task al DAG.
    public func addTasks(_ batch: [TaskNode]) throws {
        for task in batch {
            try addTask(task)
        }
    }

    /// Aggiorna lo stato di un task.
    public func updateTaskStatus(_ taskId: String, status: TaskStatus) {
        guard var task = tasks[taskId], task.status != status else { return }
        adjustStatusCounts(from: task.status, to: status)
        task.status = status
        tasks[taskId] = task
        refreshReadyState(for: taskId)
        refreshDependents(of: taskId)
    }

    /// Incrementa i tentativi di un task e lo rimette in pending.
    /// Se superato maxRetryCount, marca il task come .failed.
    public func scheduleRetry(_ taskId: String, delayMs: Int = 0) {
        guard var task = tasks[taskId] else { return }

        retryCountByTask[taskId, default: 0] += 1
        let retries = retryCountByTask[taskId, default: 0]

        if retries > maxRetryCount {
            NSLog("[DagScheduler] task %@ exceeded max retries (%d), marking failed", taskId, maxRetryCount)
            adjustStatusCounts(from: task.status, to: .failed)
            task.status = .failed
            tasks[taskId] = task
            refreshReadyState(for: taskId)
            refreshDependents(of: taskId)
            return
        }

        task.attempts += 1
        adjustStatusCounts(from: task.status, to: .pending)
        task.status = .pending
        task.waitingSince = Date().addingTimeInterval(Double(max(0, delayMs)) / 1000.0)
        tasks[taskId] = task
        refreshReadyState(for: taskId)
        refreshDependents(of: taskId)
    }

    /// Imposta waitingSince su un task (per starvation prevention).
    public func markWaiting(_ taskId: String) {
        guard var task = tasks[taskId] else { return }
        task.waitingSince = Date()
        tasks[taskId] = task
    }

    /// Segna un task come context-enriched (explorer completato).
    public func markContextEnriched(_ taskId: String) {
        tasks[taskId]?.contextEnriched = true
    }

    public func setPreferredAgentRole(_ taskId: String, role: AgentRole?) {
        tasks[taskId]?.preferredAgentRole = role
    }

    // MARK: - Ready Tasks

    /// Restituisce i task pronti per l'esecuzione:
    /// - status == .pending
    /// - tutte le dipendenze sono .completed
    ///
    /// Ordinati per effective_priority desc, taskId asc (§5.11 determinismo).
    public func getReadyTasks(now: Date = Date()) -> [TaskNode] {
        let ready = readyTaskIDs.compactMap { taskId -> TaskNode? in
            guard let task = tasks[taskId], task.status == .pending else { return nil }
            if let waitingSince = task.waitingSince, waitingSince > now {
                return nil
            }
            return task
        }
        return priorityCalculator.sorted(Array(ready), now: now)
    }

    /// Restituisce il task ready a più basso rischio (per probe circuit breaker §5.4).
    public func getLowestRiskReadyTask(now: Date = Date()) -> TaskNode? {
        let ready = getReadyTasks(now: now)
        return ready.min { a, b in
            riskOrdinal(a.risk) < riskOrdinal(b.risk)
        }
    }

    // MARK: - Query

    /// Restituisce un task per ID.
    public func task(byId id: String) -> TaskNode? {
        tasks[id]
    }

    /// Tutti i task registrati.
    public var allTasks: [TaskNode] {
        Array(tasks.values)
    }

    /// Numero totale di task.
    public var taskCount: Int {
        tasks.count
    }

    /// True se tutti i task sono in stato terminale (completed o failed/cancelled).
    public var allTasksTerminal: Bool {
        let terminal = countByStatus(.completed)
            + countByStatus(.blocked)
            + countByStatus(.failed)
            + countByStatus(.cancelled)
        return terminal == tasks.count
    }

    /// Conta task per stato.
    public func countByStatus(_ status: TaskStatus) -> Int {
        statusCounts[status, default: 0]
    }

    /// Failure rate percentuale.
    public var failureRatePercent: Double {
        let total = tasks.count
        guard total > 0 else { return 0 }
        let failed = countByStatus(.failed)
        return Double(failed) / Double(total) * 100.0
    }

    // MARK: - Validation

    /// Valida che tutte le dipendenze referenziate esistano.
    public func validateDependencies() throws {
        for task in tasks.values {
            for dep in task.dependsOn {
                guard tasks[dep] != nil else {
                    throw DagSchedulerError.dependencyNotFound(
                        taskId: task.taskId,
                        missingDep: dep
                    )
                }
            }
        }
    }

    /// Verifica aciclicità del DAG con Kahn's algorithm.
    public func validateAcyclic() throws {
        var inDegree: [String: Int] = [:]
        for task in tasks.values {
            inDegree[task.taskId] = inDegree[task.taskId] ?? 0
            for dep in task.dependsOn {
                inDegree[task.taskId, default: 0] += 1
                _ = inDegree[dep] ?? { inDegree[dep] = 0; return 0 }()
            }
        }

        var queue = inDegree.filter { $0.value == 0 }.map(\.key)
        var visited = 0

        while !queue.isEmpty {
            let node = queue.removeFirst()
            visited += 1

            for task in tasks.values where task.dependsOn.contains(node) {
                inDegree[task.taskId, default: 0] -= 1
                if inDegree[task.taskId] == 0 {
                    queue.append(task.taskId)
                }
            }
        }

        if visited < tasks.count {
            let cyclic = inDegree.filter { $0.value > 0 }.map(\.key).sorted()
            throw DagSchedulerError.cyclicDependency(involved: cyclic)
        }
    }

    // MARK: - Timeout

    /// Controlla task in attesa troppo a lungo e li marca come .failed.
    public func timeoutStaleTasks(now: Date = Date()) {
        let timeoutInterval = Double(maxRetryTimeoutMs) / 1000.0
        for (taskId, task) in tasks {
            guard task.status == .pending,
                  let waitingSince = task.waitingSince else { continue }
            if now.timeIntervalSince(waitingSince) > timeoutInterval {
                NSLog("[DagScheduler] task %@ timed out (waiting since %@), marking failed", taskId, "\(waitingSince)")
                updateTaskStatus(taskId, status: .failed)
            }
        }
    }

    // MARK: - Reset

    public func reset() {
        tasks.removeAll()
        dependentsByTask.removeAll()
        readyTaskIDs.removeAll()
        statusCounts.removeAll()
        retryCountByTask.removeAll()
    }

    // MARK: - Private

    private func adjustStatusCounts(from oldStatus: TaskStatus?, to newStatus: TaskStatus?) {
        if let oldStatus {
            statusCounts[oldStatus, default: 0] = max(0, statusCounts[oldStatus, default: 0] - 1)
        }
        if let newStatus {
            statusCounts[newStatus, default: 0] += 1
        }
    }

    private func refreshDependents(of taskId: String) {
        for dependentId in dependentsByTask[taskId] ?? [] {
            refreshReadyState(for: dependentId)
        }
    }

    private func refreshReadyState(for taskId: String) {
        guard let task = tasks[taskId] else {
            readyTaskIDs.remove(taskId)
            return
        }

        if isStructurallyReady(task) {
            readyTaskIDs.insert(taskId)
        } else {
            readyTaskIDs.remove(taskId)
        }
    }

    private func isStructurallyReady(_ task: TaskNode) -> Bool {
        guard task.status == .pending else { return false }
        return task.dependsOn.allSatisfy { dependencyId in
            tasks[dependencyId]?.status == .completed
        }
    }

    private func riskOrdinal(_ risk: RiskLevel) -> Int {
        switch risk {
        case .low:      0
        case .medium:   1
        case .high:     2
        case .critical: 3
        }
    }
}
