import Foundation

public enum ReviewSessionPhase: String, Sendable, Codable {
    case idle
    case analyzing
    case fixing
    case testing
    case reReviewing = "re_reviewing"
    case completed
    case failed
}

public enum ReviewSessionStage: String, Sendable, Codable {
    case idle
    case intake
    case analysis
    case findings
    case fixing
    case testing
    case reReview
    case completed
    case failed
}

public enum ReviewSessionTestStatus: String, Sendable, Codable {
    case passed
    case failed
    case inconclusive
}

public struct ReviewSessionScope: Sendable, Codable {
    public let type: ScopeType
    public let files: [String]
    public let ref: String?

    public enum ScopeType: String, Sendable, Codable {
        case uncommitted
        case staged
        case againstRef = "against_ref"
    }

    public var description: String {
        switch type {
        case .uncommitted:
            return "uncommitted changes (\(files.count) files)"
        case .staged:
            return "staged changes (\(files.count) files)"
        case .againstRef:
            return "vs \(ref ?? "unknown") (\(files.count) files)"
        }
    }

    public init(type: ScopeType, files: [String], ref: String? = nil) {
        self.type = type
        self.files = files
        self.ref = ref
    }
}

public struct SessionConfig: Sendable, Codable {
    public let maxWorkers: Int
    public let maxRounds: Int
    public let analysisBackend: String
    public let executionBackend: String

    public static let `default` = SessionConfig(
        maxWorkers: 6,
        maxRounds: 3,
        analysisBackend: "codex",
        executionBackend: "codex"
    )

    public init(
        maxWorkers: Int = 6,
        maxRounds: Int = 3,
        analysisBackend: String = "codex",
        executionBackend: String = "codex"
    ) {
        self.maxWorkers = max(1, min(12, maxWorkers))
        self.maxRounds = max(1, min(10, maxRounds))
        self.analysisBackend = analysisBackend
        self.executionBackend = executionBackend
    }
}

public struct CodeReviewSessionSnapshot: Sendable, Codable {
    public let sessionId: String
    public let conversationId: UUID?
    public let phase: ReviewSessionPhase
    public let stage: ReviewSessionStage
    public let findings: [CodeReviewFinding]
    public let events: [CodeReviewSessionEvent]
    public let config: SessionConfig
    public let scope: ReviewSessionScope?
    public let currentRound: Int
    public let activeWorkerCount: Int
    public let startedAt: Date?
    public let completedAt: Date?
    public let analysisCompletedAt: Date?
    public let lastError: String?
    public let currentJobId: String?
    public let lastTestStatus: ReviewSessionTestStatus?
    public let lastUpdatedAt: Date

    public init(
        sessionId: String,
        conversationId: UUID?,
        phase: ReviewSessionPhase,
        stage: ReviewSessionStage,
        findings: [CodeReviewFinding],
        events: [CodeReviewSessionEvent],
        config: SessionConfig,
        scope: ReviewSessionScope?,
        currentRound: Int,
        activeWorkerCount: Int,
        startedAt: Date?,
        completedAt: Date?,
        analysisCompletedAt: Date?,
        lastError: String?,
        currentJobId: String?,
        lastTestStatus: ReviewSessionTestStatus?,
        lastUpdatedAt: Date
    ) {
        self.sessionId = sessionId
        self.conversationId = conversationId
        self.phase = phase
        self.stage = stage
        self.findings = findings
        self.events = events
        self.config = config
        self.scope = scope
        self.currentRound = currentRound
        self.activeWorkerCount = activeWorkerCount
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.analysisCompletedAt = analysisCompletedAt
        self.lastError = lastError
        self.currentJobId = currentJobId
        self.lastTestStatus = lastTestStatus
        self.lastUpdatedAt = lastUpdatedAt
    }

    public var findingsByFile: [String: [CodeReviewFinding]] {
        Dictionary(grouping: findings, by: \.filePath)
    }

    public var findingsBySeverity: [FindingSeverity: [CodeReviewFinding]] {
        Dictionary(grouping: findings, by: \.severity)
    }

    public var openFindings: [CodeReviewFinding] {
        findings.filter { $0.status == .open }
    }

    public var isActive: Bool {
        switch phase {
        case .analyzing, .fixing, .testing, .reReviewing:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    public var statusSummary: String {
        let total = findings.count
        let open = findings.filter { $0.status == .open }.count
        let fixed = findings.filter { $0.status == .fixApplied }.count
        let dismissed = findings.filter {
            $0.status == .dismissed || $0.status == .wontFix
        }.count
        return "\(total) findings: \(open) open, \(fixed) fixed, \(dismissed) dismissed"
    }
}
