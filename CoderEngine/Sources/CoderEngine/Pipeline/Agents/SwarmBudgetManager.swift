import Foundation

// MARK: - SwarmBudgetManager

/// Gestisce i limiti di agenti per ruolo e globali per job (§8.5).
///
/// Supporta budget statico e adattivo. In modalità adaptive,
/// i limiti vengono scalati in base a complessità, rischio e tipo task.
public actor SwarmBudgetManager {

    private let config: SwarmBudgetConfig
    private var activeByTaskAndRole: [String: [AgentRole: Int]] = [:]
    private var totalActive: Int = 0
    private var activeByProvider: [String: Int] = [:]

    // MARK: - Metrics

    private(set) var totalReservations: Int = 0
    private(set) var totalRejections: Int = 0
    private(set) var adaptiveScaleUpCount: Int = 0
    private(set) var adaptiveScaleDownCount: Int = 0

    public init(config: SwarmBudgetConfig = SwarmBudgetConfig()) {
        self.config = config
    }

    // MARK: - Capacity Check

    /// Verifica se c'è capacità per un agente di questo ruolo per il task dato.
    public func hasCapacity(
        task: TaskNode,
        role: AgentRole,
        providerId: String? = nil
    ) -> Bool {
        if totalActive >= config.maxTotalActiveAgents {
            return false
        }

        if let pid = providerId, (activeByProvider[pid] ?? 0) >= config.maxAgentsPerProvider {
            return false
        }

        let currentForRole = activeByTaskAndRole[task.taskId]?[role] ?? 0
        let limit = effectiveLimit(for: role, task: task)
        return currentForRole < limit
    }

    // MARK: - Reserve / Release

    /// Riserva uno slot per il ruolo nel task. Restituisce false se budget esaurito.
    @discardableResult
    public func reserve(
        task: TaskNode,
        role: AgentRole,
        providerId: String? = nil
    ) -> Bool {
        guard hasCapacity(task: task, role: role, providerId: providerId) else {
            totalRejections += 1
            return false
        }

        if activeByTaskAndRole[task.taskId] == nil {
            activeByTaskAndRole[task.taskId] = [:]
        }
        activeByTaskAndRole[task.taskId]?[role, default: 0] += 1
        totalActive += 1
        totalReservations += 1

        if let pid = providerId {
            activeByProvider[pid, default: 0] += 1
        }

        return true
    }

    /// Rilascia uno slot per il ruolo nel task.
    public func release(
        task: TaskNode,
        role: AgentRole,
        providerId: String? = nil
    ) {
        let current = activeByTaskAndRole[task.taskId]?[role] ?? 0
        if current > 0 {
            activeByTaskAndRole[task.taskId]?[role] = current - 1
            totalActive = max(0, totalActive - 1)
        }

        if let pid = providerId {
            let provCount = activeByProvider[pid] ?? 0
            if provCount > 0 {
                activeByProvider[pid] = provCount - 1
            }
        }
    }

    // MARK: - Effective Limit

    /// Calcola il limite effettivo per un ruolo, tenendo conto del budget adattivo.
    public func effectiveLimit(for role: AgentRole, task: TaskNode) -> Int {
        let base = baseLimit(for: role)
        guard config.adaptive else {
            return base
        }

        let multiplier = adaptiveMultiplier(for: task)

        if multiplier > 1.0 {
            adaptiveScaleUpCount += 1
        } else if multiplier < 1.0 {
            adaptiveScaleDownCount += 1
        }

        let adapted = max(1, Int((Double(base) * multiplier).rounded()))
        return adapted
    }

    // MARK: - Adaptive Multiplier (§8.5)

    /// Calcola il moltiplicatore adattivo basato su complessità, rischio e tipo task.
    /// Clamped tra 0.5 e 2.0.
    public func adaptiveMultiplier(for task: TaskNode) -> Double {
        let complexity = complexityFactor(fileCount: task.fileScope.count)
        let risk = riskFactor(risk: task.risk)
        let scope = scopeFactor(taskType: task.taskType)

        let raw = (complexity + risk + scope) / 3.0
        return max(0.5, min(2.0, raw))
    }

    // MARK: - Query

    public var currentTotalActive: Int { totalActive }

    public func activeCount(taskId: String, role: AgentRole) -> Int {
        activeByTaskAndRole[taskId]?[role] ?? 0
    }

    public var utilizationPercent: Double {
        guard config.maxTotalActiveAgents > 0 else { return 0 }
        return Double(totalActive) / Double(config.maxTotalActiveAgents) * 100.0
    }

    // MARK: - Reset

    public func reset() {
        activeByTaskAndRole.removeAll()
        activeByProvider.removeAll()
        totalActive = 0
        totalReservations = 0
        totalRejections = 0
        adaptiveScaleUpCount = 0
        adaptiveScaleDownCount = 0
    }

    // MARK: - Private

    private func baseLimit(for role: AgentRole) -> Int {
        switch role {
        case .explorer:        config.maxExplorersPerTask
        case .coder:           config.maxCodersPerTask
        case .reviewer:        config.maxReviewersPerPatch
        case .testWriter:      config.maxTestWritersPerTask
        case .docWriter:       config.maxDocWritersPerTask
        case .debugger:        config.maxCodersPerTask
        case .securityAuditor: 1
        case .planner:         1
        }
    }

    private func complexityFactor(fileCount: Int) -> Double {
        switch fileCount {
        case ...2:   0.5
        case 3...5:  1.0
        case 6...10: 1.5
        default:     2.0
        }
    }

    private func riskFactor(risk: RiskLevel) -> Double {
        switch risk {
        case .low:      0.5
        case .medium:   1.0
        case .high:     1.5
        case .critical: 2.0
        }
    }

    private func scopeFactor(taskType: TaskType) -> Double {
        switch taskType {
        case .test:     0.5
        case .docs:     0.5
        case .bugfix:   1.0
        case .refactor: 1.5
        case .feature:  1.5
        }
    }
}
