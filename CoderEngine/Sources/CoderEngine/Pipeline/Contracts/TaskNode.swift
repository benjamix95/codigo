import Foundation

// MARK: - ActiveAgent

/// Record di un agente attivo/completato assegnato al task (§6.13).
public struct ActiveAgent: Codable, Sendable, Equatable {
    public var agentName: String
    public var agentId: String
    public var status: TaskStatus

    public init(agentName: String, agentId: String, status: TaskStatus = .pending) {
        self.agentName = agentName
        self.agentId = agentId
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case agentName = "agent_name"
        case agentId = "agent_id"
        case status
    }
}

// MARK: - TaskNode

/// Contratto dati del nodo task nel DAG (§6.2).
public struct TaskNode: Codable, Sendable, Equatable, Identifiable {
    public var id: String { taskId }

    public var taskId: String
    public var title: String
    public var taskLabel: String?
    public var dependsOn: [String]
    public var priority: Int
    public var risk: RiskLevel
    public var taskType: TaskType
    public var executionStyle: TaskExecutionStyle
    public var preferredAgentRole: AgentRole?
    public var debugStage: DebugStageKind?
    public var fileScope: [String]
    public var symbolScope: [String]
    public var metadata: [String: String]
    public var status: TaskStatus
    public var attempts: Int
    public var maxAttempts: Int
    public var timeoutMs: Int
    public var activeAgents: [ActiveAgent]
    public var waitingSince: Date?
    public var contextEnriched: Bool

    public init(
        taskId: String,
        title: String,
        taskLabel: String? = nil,
        dependsOn: [String] = [],
        priority: Int = 50,
        risk: RiskLevel = .medium,
        taskType: TaskType = .feature,
        executionStyle: TaskExecutionStyle = .multiAgentFlow,
        preferredAgentRole: AgentRole? = nil,
        debugStage: DebugStageKind? = nil,
        fileScope: [String] = [],
        symbolScope: [String] = [],
        metadata: [String: String] = [:],
        status: TaskStatus = .pending,
        attempts: Int = 0,
        maxAttempts: Int = 3,
        timeoutMs: Int = 120_000,
        activeAgents: [ActiveAgent] = [],
        waitingSince: Date? = nil,
        contextEnriched: Bool = false
    ) {
        self.taskId = taskId
        self.title = title
        self.taskLabel = taskLabel
        self.dependsOn = dependsOn
        self.priority = priority
        self.risk = risk
        self.taskType = taskType
        self.executionStyle = executionStyle
        self.preferredAgentRole = preferredAgentRole
        self.debugStage = debugStage
        self.fileScope = fileScope
        self.symbolScope = symbolScope
        self.metadata = metadata
        self.status = status
        self.attempts = attempts
        self.maxAttempts = maxAttempts
        self.timeoutMs = timeoutMs
        self.activeAgents = activeAgents
        self.waitingSince = waitingSince
        self.contextEnriched = contextEnriched
    }

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case title
        case taskLabel = "task_label"
        case dependsOn = "depends_on"
        case priority
        case risk
        case taskType = "task_type"
        case executionStyle = "execution_style"
        case preferredAgentRole = "preferred_agent_role"
        case debugStage = "debug_stage"
        case fileScope = "file_scope"
        case symbolScope = "symbol_scope"
        case metadata
        case status
        case attempts
        case maxAttempts = "max_attempts"
        case timeoutMs = "timeout_ms"
        case activeAgents = "active_agents"
        case waitingSince = "waiting_since"
        case contextEnriched = "context_enriched"
    }

    /// Genera il task_label dal titolo (§6.13) — max 30 char, PascalCase slug.
    public mutating func deriveTaskLabel() {
        let words = title
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let joined = words.joined()
        taskLabel = String(joined.prefix(30))
    }
}

extension TaskNode: PipelineValidatable {
    public func validate() throws {
        let c = "TaskNode"
        try PipelineValidationHelpers.requireNonEmpty(taskId, field: "task_id", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(title, field: "title", contract: c)
        try PipelineValidationHelpers.requireRange(
            priority, range: 0...100, field: "priority", contract: c
        )
        try PipelineValidationHelpers.requireRange(
            maxAttempts, range: 1...10, field: "max_attempts", contract: c
        )
        try PipelineValidationHelpers.requireRange(
            timeoutMs, range: 1_000...600_000, field: "timeout_ms", contract: c
        )
        if executionStyle == .singleAgent && preferredAgentRole == nil {
            throw PipelineValidationError.missingRequiredField(
                field: "preferred_agent_role",
                contract: c
            )
        }
        if attempts < 0 || attempts > maxAttempts {
            throw PipelineValidationError.valueOutOfRange(
                field: "attempts", contract: c,
                value: "\(attempts)", range: "0...\(maxAttempts)"
            )
        }
    }
}
