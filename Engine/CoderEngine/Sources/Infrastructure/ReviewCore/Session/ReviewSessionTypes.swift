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
        case workspace
        case codebase
        case againstRef = "against_ref"
    }

    public var description: String {
        switch type {
        case .uncommitted:
            return "uncommitted changes (\(files.count) files)"
        case .staged:
            return "staged changes (\(files.count) files)"
        case .workspace:
            return "workspace source files (\(files.count) files)"
        case .codebase:
            return "indexed codebase (\(files.count) files)"
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
    public let analysisOnly: Bool

    public static let `default` = SessionConfig(
        maxWorkers: 6,
        maxRounds: 3,
        analysisBackend: "codex",
        executionBackend: "codex",
        analysisOnly: false
    )

    public init(
        maxWorkers: Int = 6,
        maxRounds: Int = 3,
        analysisBackend: String = "codex",
        executionBackend: String = "codex",
        analysisOnly: Bool = false
    ) {
        self.maxWorkers = max(1, min(12, maxWorkers))
        self.maxRounds = max(1, min(10, maxRounds))
        self.analysisBackend = analysisBackend
        self.executionBackend = executionBackend
        self.analysisOnly = analysisOnly
    }

    enum CodingKeys: String, CodingKey {
        case maxWorkers
        case maxRounds
        case analysisBackend
        case executionBackend
        case analysisOnly
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maxWorkers: try container.decodeIfPresent(Int.self, forKey: .maxWorkers) ?? 6,
            maxRounds: try container.decodeIfPresent(Int.self, forKey: .maxRounds) ?? 3,
            analysisBackend: try container.decodeIfPresent(String.self, forKey: .analysisBackend) ?? "codex",
            executionBackend: try container.decodeIfPresent(String.self, forKey: .executionBackend) ?? "codex",
            analysisOnly: try container.decodeIfPresent(Bool.self, forKey: .analysisOnly) ?? false
        )
    }

    public var reviewCommandPayload: [String: String] {
        [
            "max_workers": String(maxWorkers),
            "max_rounds": String(maxRounds),
            "analysis_backend": analysisBackend,
            "execution_backend": executionBackend,
            "analysis_only": analysisOnly ? "true" : "false",
        ]
    }
}

public struct ReviewAuditSnapshot: Sendable, Codable, Equatable {
    public let toolCoverage: [String: Bool]
    public let toolDurationsMs: [String: Int]
    public let toolFindingsCounts: [String: Int]
    public let toolAdapters: [String: [String]]

    public static let empty = ReviewAuditSnapshot()

    public init(
        toolCoverage: [String: Bool] = [:],
        toolDurationsMs: [String: Int] = [:],
        toolFindingsCounts: [String: Int] = [:],
        toolAdapters: [String: [String]] = [:]
    ) {
        self.toolCoverage = toolCoverage
        self.toolDurationsMs = toolDurationsMs
        self.toolFindingsCounts = toolFindingsCounts
        self.toolAdapters = toolAdapters
    }
}

public struct CodeReviewSessionSnapshot: Sendable, Codable {
    public let sessionId: String
    public let conversationId: UUID?
    public let mutationSequence: UInt64
    public let phase: ReviewSessionPhase
    public let stage: ReviewSessionStage
    public let findings: [CodeReviewFinding]
    public let candidates: [ReviewCandidate]
    public let patches: [ReviewPatchArtifact]
    public let events: [CodeReviewSessionEvent]
    public let config: SessionConfig
    public let scope: ReviewSessionScope?
    public let workspacePath: String?
    public let currentRound: Int
    public let activeWorkerCount: Int
    public let startedAt: Date?
    public let completedAt: Date?
    public let analysisCompletedAt: Date?
    public let lastError: String?
    public let currentJobId: String?
    public let lastTestStatus: ReviewSessionTestStatus?
    public let audit: ReviewAuditSnapshot
    public let outcome: ReviewSessionOutcome
    public let verifiedFindings: VerifiedFindingsSessionEnvelope?
    public let phaseLedger: [ReviewPipelinePhaseLedgerEntry]
    public let fileLedger: [ReviewPipelineFileLedgerEntry]
    public let lastUpdatedAt: Date

    public init(
        sessionId: String,
        conversationId: UUID?,
        mutationSequence: UInt64 = 0,
        phase: ReviewSessionPhase,
        stage: ReviewSessionStage,
        findings: [CodeReviewFinding],
        candidates: [ReviewCandidate] = [],
        patches: [ReviewPatchArtifact] = [],
        events: [CodeReviewSessionEvent],
        config: SessionConfig,
        scope: ReviewSessionScope?,
        workspacePath: String? = nil,
        currentRound: Int,
        activeWorkerCount: Int,
        startedAt: Date?,
        completedAt: Date?,
        analysisCompletedAt: Date?,
        lastError: String?,
        currentJobId: String?,
        lastTestStatus: ReviewSessionTestStatus?,
        audit: ReviewAuditSnapshot = .empty,
        outcome: ReviewSessionOutcome = .empty,
        verifiedFindings: VerifiedFindingsSessionEnvelope? = nil,
        phaseLedger: [ReviewPipelinePhaseLedgerEntry] = [],
        fileLedger: [ReviewPipelineFileLedgerEntry] = [],
        lastUpdatedAt: Date
    ) {
        self.sessionId = sessionId
        self.conversationId = conversationId
        self.mutationSequence = mutationSequence
        self.phase = phase
        self.stage = stage
        self.findings = findings
        self.candidates = candidates
        self.patches = patches
        self.events = events
        self.config = config
        self.scope = scope
        self.workspacePath = workspacePath
        self.currentRound = currentRound
        self.activeWorkerCount = activeWorkerCount
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.analysisCompletedAt = analysisCompletedAt
        self.lastError = lastError
        self.currentJobId = currentJobId
        self.lastTestStatus = lastTestStatus
        self.audit = audit
        self.outcome = outcome
        self.verifiedFindings = verifiedFindings
        self.phaseLedger = phaseLedger
        self.fileLedger = fileLedger
        self.lastUpdatedAt = lastUpdatedAt
    }

    enum CodingKeys: String, CodingKey {
        case sessionId
        case conversationId
        case mutationSequence
        case phase
        case stage
        case findings
        case candidates
        case patches
        case events
        case config
        case scope
        case workspacePath
        case currentRound
        case activeWorkerCount
        case startedAt
        case completedAt
        case analysisCompletedAt
        case lastError
        case currentJobId
        case lastTestStatus
        case audit
        case outcome
        case verifiedFindings
        case phaseLedger
        case fileLedger
        case lastUpdatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        conversationId = try container.decodeIfPresent(UUID.self, forKey: .conversationId)
        mutationSequence = try container.decodeIfPresent(
            UInt64.self,
            forKey: .mutationSequence
        ) ?? 0
        phase = try container.decode(ReviewSessionPhase.self, forKey: .phase)
        stage = try container.decode(ReviewSessionStage.self, forKey: .stage)
        findings = try container.decode([CodeReviewFinding].self, forKey: .findings)
        candidates = try container.decodeIfPresent([ReviewCandidate].self, forKey: .candidates) ?? []
        patches = try container.decodeIfPresent([ReviewPatchArtifact].self, forKey: .patches) ?? []
        events = try container.decode([CodeReviewSessionEvent].self, forKey: .events)
        config = try container.decode(SessionConfig.self, forKey: .config)
        scope = try container.decodeIfPresent(ReviewSessionScope.self, forKey: .scope)
        workspacePath = try container.decodeIfPresent(String.self, forKey: .workspacePath)
        currentRound = try container.decode(Int.self, forKey: .currentRound)
        activeWorkerCount = try container.decode(Int.self, forKey: .activeWorkerCount)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        analysisCompletedAt = try container.decodeIfPresent(Date.self, forKey: .analysisCompletedAt)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        currentJobId = try container.decodeIfPresent(String.self, forKey: .currentJobId)
        lastTestStatus = try container.decodeIfPresent(
            ReviewSessionTestStatus.self,
            forKey: .lastTestStatus
        )
        audit = try container.decodeIfPresent(ReviewAuditSnapshot.self, forKey: .audit) ?? .empty
        outcome = try container.decodeIfPresent(ReviewSessionOutcome.self, forKey: .outcome) ?? .empty
        verifiedFindings = try container.decodeIfPresent(
            VerifiedFindingsSessionEnvelope.self,
            forKey: .verifiedFindings
        )
        phaseLedger = try container.decodeIfPresent(
            [ReviewPipelinePhaseLedgerEntry].self,
            forKey: .phaseLedger
        ) ?? []
        fileLedger = try container.decodeIfPresent(
            [ReviewPipelineFileLedgerEntry].self,
            forKey: .fileLedger
        ) ?? []
        lastUpdatedAt = try container.decode(Date.self, forKey: .lastUpdatedAt)
    }
}
