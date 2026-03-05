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
    private let priorityCalculator: PriorityCalculator

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
    }

    /// Aggiunge un batch di task al DAG.
    public func addTasks(_ batch: [TaskNode]) throws {
        for task in batch {
            try addTask(task)
        }
    }

    /// Aggiorna lo stato di un task.
    public func updateTaskStatus(_ taskId: String, status: TaskStatus) {
        tasks[taskId]?.status = status
    }

    /// Incrementa i tentativi di un task e lo rimette in pending.
    public func scheduleRetry(_ taskId: String) {
        guard var task = tasks[taskId] else { return }
        task.attempts += 1
        task.status = .pending
        task.waitingSince = Date()
        tasks[taskId] = task
    }

    /// Imposta waitingSince su un task (per starvation prevention).
    public func markWaiting(_ taskId: String) {
        tasks[taskId]?.waitingSince = Date()
    }

    // MARK: - Ready Tasks

    /// Restituisce i task pronti per l'esecuzione:
    /// - status == .pending
    /// - tutte le dipendenze sono .completed
    ///
    /// Ordinati per effective_priority desc, taskId asc (§5.11 determinismo).
    public func getReadyTasks(now: Date = Date()) -> [TaskNode] {
        let ready = tasks.values.filter { task in
            guard task.status == .pending else { return false }
            return task.dependsOn.allSatisfy { depId in
                tasks[depId]?.status == .completed
            }
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
        tasks.values.allSatisfy { task in
            task.status == .completed ||
            task.status == .failed ||
            task.status == .cancelled
        }
    }

    /// Conta task per stato.
    public func countByStatus(_ status: TaskStatus) -> Int {
        tasks.values.filter { $0.status == status }.count
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

    // MARK: - Reset

    public func reset() {
        tasks.removeAll()
    }

    // MARK: - Private

    private func riskOrdinal(_ risk: RiskLevel) -> Int {
        switch risk {
        case .low:      0
        case .medium:   1
        case .high:     2
        case .critical: 3
        }
    }
}
