import Foundation

// MARK: - ReviewFinding

/// Singolo finding della review (§10).
public struct ReviewFinding: Codable, Sendable, Equatable, Identifiable {
    public var id: String { findingId }

    public var findingId: String
    public var file: String
    public var line: Int?
    public var severity: FindingSeverity
    public var status: FindingStatus
    public var message: String
    public var suggestedFix: String?

    public init(
        findingId: String,
        file: String,
        line: Int? = nil,
        severity: FindingSeverity,
        status: FindingStatus = .open,
        message: String,
        suggestedFix: String? = nil
    ) {
        self.findingId = findingId
        self.file = file
        self.line = line
        self.severity = severity
        self.status = status
        self.message = message
        self.suggestedFix = suggestedFix
    }

    enum CodingKeys: String, CodingKey {
        case findingId = "finding_id"
        case file
        case line
        case severity
        case status
        case message
        case suggestedFix = "suggested_fix"
    }
}

// MARK: - ReviewSession

/// Contratto dati della sessione di review (§6.4).
public struct ReviewSession: Codable, Sendable, Equatable, Identifiable {
    public var id: String { sessionId }

    public var sessionId: String
    public var jobId: String
    public var taskId: String
    public var scope: ReviewScope
    public var maxWorkers: Int
    public var maxRounds: Int
    public var analysisBackend: String
    public var executionBackend: String
    public var phase: ReviewPhase
    public var currentRound: Int
    public var findings: [ReviewFinding]

    public var findingsCount: Int { findings.count }

    public init(
        sessionId: String,
        jobId: String,
        taskId: String,
        scope: ReviewScope = .uncommitted,
        maxWorkers: Int = 6,
        maxRounds: Int = 3,
        analysisBackend: String = "codex",
        executionBackend: String = "codex",
        phase: ReviewPhase = .pending,
        currentRound: Int = 0,
        findings: [ReviewFinding] = []
    ) {
        self.sessionId = sessionId
        self.jobId = jobId
        self.taskId = taskId
        self.scope = scope
        self.maxWorkers = maxWorkers
        self.maxRounds = maxRounds
        self.analysisBackend = analysisBackend
        self.executionBackend = executionBackend
        self.phase = phase
        self.currentRound = currentRound
        self.findings = findings
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case jobId = "job_id"
        case taskId = "task_id"
        case scope
        case maxWorkers = "max_workers"
        case maxRounds = "max_rounds"
        case analysisBackend = "analysis_backend"
        case executionBackend = "execution_backend"
        case phase
        case currentRound = "current_round"
        case findings
    }

    /// True se ci sono finding critici aperti.
    public var hasCriticalFindings: Bool {
        findings.contains { (f: ReviewFinding) -> Bool in
            f.severity == .critical && f.status == .open
        }
    }

    /// True se dopo maxRounds persistono findings bloccanti (§15 convergence rule).
    public var isConvergenceBlocked: Bool {
        currentRound >= maxRounds && hasCriticalFindings
    }
}

extension ReviewSession: PipelineValidatable {
    public func validate() throws {
        let c = "ReviewSession"
        try PipelineValidationHelpers.requireNonEmpty(sessionId, field: "session_id", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(jobId, field: "job_id", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(taskId, field: "task_id", contract: c)
        try PipelineValidationHelpers.requireRange(
            maxWorkers, range: 1...12, field: "max_workers", contract: c
        )
        try PipelineValidationHelpers.requireRange(
            maxRounds, range: 1...10, field: "max_rounds", contract: c
        )
    }
}
