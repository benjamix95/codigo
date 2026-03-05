import Foundation

// MARK: - ErrorBudget

/// Configurazione error budget per il job (§6.1).
public struct ErrorBudget: Codable, Sendable, Equatable {
    public var maxFailedTasksPercent: Int
    public var maxConsecutiveFailures: Int

    public init(
        maxFailedTasksPercent: Int = 30,
        maxConsecutiveFailures: Int = 5
    ) {
        self.maxFailedTasksPercent = maxFailedTasksPercent
        self.maxConsecutiveFailures = maxConsecutiveFailures
    }

    enum CodingKeys: String, CodingKey {
        case maxFailedTasksPercent = "max_failed_tasks_percent"
        case maxConsecutiveFailures = "max_consecutive_failures"
    }
}

extension ErrorBudget: PipelineValidatable {
    public func validate() throws {
        try PipelineValidationHelpers.requireRange(
            maxFailedTasksPercent, range: 1...100,
            field: "max_failed_tasks_percent", contract: "ErrorBudget"
        )
        try PipelineValidationHelpers.requireRange(
            maxConsecutiveFailures, range: 1...20,
            field: "max_consecutive_failures", contract: "ErrorBudget"
        )
    }
}

// MARK: - SwarmBudgetConfig

/// Configurazione swarm budget (§8.5).
public struct SwarmBudgetConfig: Codable, Sendable, Equatable {
    public var maxExplorersPerTask: Int
    public var maxCodersPerTask: Int
    public var maxReviewersPerPatch: Int
    public var maxTestWritersPerTask: Int
    public var maxDocWritersPerTask: Int
    public var maxTotalActiveAgents: Int
    public var maxAgentsPerProvider: Int
    public var adaptive: Bool

    public init(
        maxExplorersPerTask: Int = 3,
        maxCodersPerTask: Int = 2,
        maxReviewersPerPatch: Int = 5,
        maxTestWritersPerTask: Int = 2,
        maxDocWritersPerTask: Int = 2,
        maxTotalActiveAgents: Int = 12,
        maxAgentsPerProvider: Int = 6,
        adaptive: Bool = true
    ) {
        self.maxExplorersPerTask = maxExplorersPerTask
        self.maxCodersPerTask = maxCodersPerTask
        self.maxReviewersPerPatch = maxReviewersPerPatch
        self.maxTestWritersPerTask = maxTestWritersPerTask
        self.maxDocWritersPerTask = maxDocWritersPerTask
        self.maxTotalActiveAgents = maxTotalActiveAgents
        self.maxAgentsPerProvider = maxAgentsPerProvider
        self.adaptive = adaptive
    }

    enum CodingKeys: String, CodingKey {
        case maxExplorersPerTask = "max_explorers_per_task"
        case maxCodersPerTask = "max_coders_per_task"
        case maxReviewersPerPatch = "max_reviewers_per_patch"
        case maxTestWritersPerTask = "max_test_writers_per_task"
        case maxDocWritersPerTask = "max_doc_writers_per_task"
        case maxTotalActiveAgents = "max_total_active_agents"
        case maxAgentsPerProvider = "max_agents_per_provider"
        case adaptive
    }
}

// MARK: - PipelineJob

/// Contratto dati del job pipeline (§6.1).
public struct PipelineJob: Codable, Sendable, Equatable {
    public var jobId: String
    public var workspace: String
    public var request: String
    public var mode: PipelineMode
    public var createdAt: Date
    public var state: JobState
    public var policyVersion: String
    public var selectedProviderProfile: String
    public var planSnapshotId: String?
    public var jobTimeoutMs: Int
    public var maxConcurrentWorkers: Int
    public var errorBudget: ErrorBudget
    public var rollbackStrategy: RollbackStrategy
    public var swarmBudget: SwarmBudgetConfig?

    public init(
        jobId: String,
        workspace: String,
        request: String,
        mode: PipelineMode = .strict,
        createdAt: Date = Date(),
        state: JobState = .intake,
        policyVersion: String = "v2.4",
        selectedProviderProfile: String = "default",
        planSnapshotId: String? = nil,
        jobTimeoutMs: Int = 1_800_000,
        maxConcurrentWorkers: Int = 4,
        errorBudget: ErrorBudget = ErrorBudget(),
        rollbackStrategy: RollbackStrategy = .gitBranch,
        swarmBudget: SwarmBudgetConfig? = nil
    ) {
        self.jobId = jobId
        self.workspace = workspace
        self.request = request
        self.mode = mode
        self.createdAt = createdAt
        self.state = state
        self.policyVersion = policyVersion
        self.selectedProviderProfile = selectedProviderProfile
        self.planSnapshotId = planSnapshotId
        self.jobTimeoutMs = jobTimeoutMs
        self.maxConcurrentWorkers = maxConcurrentWorkers
        self.errorBudget = errorBudget
        self.rollbackStrategy = rollbackStrategy
        self.swarmBudget = swarmBudget
    }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case workspace
        case request
        case mode
        case createdAt = "created_at"
        case state
        case policyVersion = "policy_version"
        case selectedProviderProfile = "selected_provider_profile"
        case planSnapshotId = "plan_snapshot_id"
        case jobTimeoutMs = "job_timeout_ms"
        case maxConcurrentWorkers = "max_concurrent_workers"
        case errorBudget = "error_budget"
        case rollbackStrategy = "rollback_strategy"
        case swarmBudget = "swarm_budget"
    }
}

extension PipelineJob: PipelineValidatable {
    public func validate() throws {
        let c = "PipelineJob"
        try PipelineValidationHelpers.requireNonEmpty(jobId, field: "job_id", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(workspace, field: "workspace", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(request, field: "request", contract: c)
        try PipelineValidationHelpers.requireRange(
            maxConcurrentWorkers, range: 1...8,
            field: "max_concurrent_workers", contract: c
        )
        try PipelineValidationHelpers.requireRange(
            jobTimeoutMs, range: 1...7_200_000,
            field: "job_timeout_ms", contract: c
        )
        try errorBudget.validate()
    }
}
