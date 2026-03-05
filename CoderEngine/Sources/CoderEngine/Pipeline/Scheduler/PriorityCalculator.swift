import Foundation

// MARK: - PriorityCalculator

/// Calcola la priorità effettiva dei task per lo scheduler (§8.4).
///
/// Formula: `effective_priority = base_priority + wait_time_factor`
/// dove `wait_time_factor = waiting_seconds / 10`
///
/// Garantisce starvation prevention: task a bassa priorità
/// guadagnano priorità col tempo di attesa.
public struct PriorityCalculator: Sendable {

    public init() {}

    /// Calcola la priorità effettiva di un task.
    ///
    /// - Parameters:
    ///   - task: il TaskNode corrente
    ///   - now: timestamp corrente (iniettabile per test deterministici)
    /// - Returns: priorità effettiva come Double (per ordinamento fine)
    public func effectivePriority(for task: TaskNode, now: Date = Date()) -> Double {
        let base = Double(task.priority)
        let waitFactor = waitTimeFactor(for: task, now: now)
        return base + waitFactor
    }

    /// Calcola il wait_time_factor per starvation prevention.
    ///
    /// Se il task ha `waitingSince` impostato, il fattore è
    /// `secondi_di_attesa / 10`. Altrimenti è 0.
    public func waitTimeFactor(for task: TaskNode, now: Date = Date()) -> Double {
        guard let waitingSince = task.waitingSince else {
            return 0
        }
        let waitingSeconds = max(0, now.timeIntervalSince(waitingSince))
        return waitingSeconds / 10.0
    }

    /// Ordina un array di task per priorità effettiva decrescente.
    /// A parità di priorità, ordina per taskId crescente (determinismo §5.11).
    public func sorted(_ tasks: [TaskNode], now: Date = Date()) -> [TaskNode] {
        tasks.sorted { a, b in
            let pa = effectivePriority(for: a, now: now)
            let pb = effectivePriority(for: b, now: now)
            if pa != pb {
                return pa > pb
            }
            return a.taskId < b.taskId
        }
    }
}
