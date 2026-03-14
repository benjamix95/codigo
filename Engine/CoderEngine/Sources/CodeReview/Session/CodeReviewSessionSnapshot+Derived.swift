import Foundation

public struct ReviewSessionOutcome: Sendable, Codable, Equatable {
    public let summary: String
    public let verifiedFindings: Int
    public let falsePositives: Int
    public let patchesReady: Int
    public let patchesApplied: Int
    public let prsOpened: Int
    public let mergedPatches: Int
    public let conflictsDetected: Int
    public let manualActionRequired: Bool
    public let testsStatus: ReviewSessionTestStatus?
    public let generatedAt: Date

    public static let empty = ReviewSessionOutcome(
        summary: "No review outcome available yet.",
        verifiedFindings: 0,
        falsePositives: 0,
        patchesReady: 0,
        patchesApplied: 0,
        prsOpened: 0,
        mergedPatches: 0,
        conflictsDetected: 0,
        manualActionRequired: false,
        testsStatus: nil,
        generatedAt: .distantPast
    )

    public init(
        summary: String,
        verifiedFindings: Int,
        falsePositives: Int,
        patchesReady: Int,
        patchesApplied: Int,
        prsOpened: Int,
        mergedPatches: Int,
        conflictsDetected: Int,
        manualActionRequired: Bool,
        testsStatus: ReviewSessionTestStatus?,
        generatedAt: Date = Date()
    ) {
        self.summary = summary
        self.verifiedFindings = verifiedFindings
        self.falsePositives = falsePositives
        self.patchesReady = patchesReady
        self.patchesApplied = patchesApplied
        self.prsOpened = prsOpened
        self.mergedPatches = mergedPatches
        self.conflictsDetected = conflictsDetected
        self.manualActionRequired = manualActionRequired
        self.testsStatus = testsStatus
        self.generatedAt = generatedAt
    }
}

public enum ReviewPipelineLedgerStatus: String, Sendable, Codable, CaseIterable {
    case pending
    case running
    case completed
    case blocked
}

public struct ReviewPipelinePhaseLedgerEntry: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let status: ReviewPipelineLedgerStatus
    public let fileCount: Int
    public let workerCount: Int
    public let findingsCount: Int
    public let startedAt: Date?
    public let completedAt: Date?
    public let summary: String?

    public init(
        id: String,
        title: String,
        status: ReviewPipelineLedgerStatus,
        fileCount: Int = 0,
        workerCount: Int = 0,
        findingsCount: Int = 0,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.fileCount = fileCount
        self.workerCount = workerCount
        self.findingsCount = findingsCount
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.summary = summary
    }
}

public struct ReviewPipelineFileLedgerEntry: Sendable, Codable, Equatable, Identifiable {
    public let path: String
    public let phaseId: String
    public let status: ReviewPipelineLedgerStatus
    public let workerIds: [String]
    public let toolIds: [String]
    public let severity: FindingSeverity?
    public let candidateCount: Int
    public let findingCount: Int
    public let patchReadyCount: Int
    public let summary: String?

    public var id: String { path }

    public init(
        path: String,
        phaseId: String,
        status: ReviewPipelineLedgerStatus,
        workerIds: [String] = [],
        toolIds: [String] = [],
        severity: FindingSeverity? = nil,
        candidateCount: Int = 0,
        findingCount: Int = 0,
        patchReadyCount: Int = 0,
        summary: String? = nil
    ) {
        self.path = path
        self.phaseId = phaseId
        self.status = status
        self.workerIds = workerIds
        self.toolIds = toolIds
        self.severity = severity
        self.candidateCount = candidateCount
        self.findingCount = findingCount
        self.patchReadyCount = patchReadyCount
        self.summary = summary
    }
}

extension CodeReviewSessionSnapshot {
    public var findingsByFile: [String: [CodeReviewFinding]] {
        Dictionary(grouping: findings, by: \.filePath)
    }

    public var findingsBySeverity: [FindingSeverity: [CodeReviewFinding]] {
        Dictionary(grouping: findings, by: \.severity)
    }

    public var findingsByOrigin: [FindingOrigin: [CodeReviewFinding]] {
        Dictionary(grouping: findings, by: \.origin)
    }

    public var findingsByCategory: [FindingCategory: [CodeReviewFinding]] {
        Dictionary(grouping: findings, by: \.category)
    }

    public var verifiedFindingsCount: Int {
        findings.count
    }

    public var falsePositiveCandidatesCount: Int {
        candidates.filter { $0.verificationStatus == .rejectedFalsePositive }.count
    }

    public var openFindings: [CodeReviewFinding] {
        findings.filter { $0.status.isOpenState }
    }

    public var blockingOpenFindings: [CodeReviewFinding] {
        openFindings.filter(\.blocking)
    }

    public var auditCoveragePercent: Double {
        guard !audit.toolCoverage.isEmpty else { return 0 }
        let covered = audit.toolCoverage.values.filter { $0 }.count
        return Double(covered) / Double(audit.toolCoverage.count) * 100.0
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
        let open = openFindings.count
        let blocking = blockingOpenFindings.count
        let applied = findings.filter { $0.status.isAppliedState }.count
        let dismissed = findings.filter {
            $0.status == .dismissed || $0.status == .wontFix
        }.count
        return "\(verifiedFindingsCount) verified, \(candidates.count) candidates, \(patches.count) patches, \(open) open (\(blocking) blocking), \(applied) applied, \(dismissed) dismissed"
    }

    public func copying(
        mutationSequence: UInt64? = nil,
        phase: ReviewSessionPhase? = nil,
        stage: ReviewSessionStage? = nil,
        findings: [CodeReviewFinding]? = nil,
        candidates: [ReviewCandidate]? = nil,
        patches: [ReviewPatchArtifact]? = nil,
        events: [CodeReviewSessionEvent]? = nil,
        config: SessionConfig? = nil,
        scope: ReviewSessionScope? = nil,
        workspacePath: String?? = nil,
        currentRound: Int? = nil,
        activeWorkerCount: Int? = nil,
        startedAt: Date?? = nil,
        completedAt: Date?? = nil,
        analysisCompletedAt: Date?? = nil,
        lastError: String?? = nil,
        currentJobId: String?? = nil,
        lastTestStatus: ReviewSessionTestStatus?? = nil,
        audit: ReviewAuditSnapshot? = nil,
        outcome: ReviewSessionOutcome? = nil,
        verifiedFindings: VerifiedFindingsSessionEnvelope?? = nil,
        phaseLedger: [ReviewPipelinePhaseLedgerEntry]? = nil,
        fileLedger: [ReviewPipelineFileLedgerEntry]? = nil,
        lastUpdatedAt: Date = Date()
    ) -> CodeReviewSessionSnapshot {
        CodeReviewSessionSnapshot(
            sessionId: sessionId,
            conversationId: conversationId,
            mutationSequence: mutationSequence ?? (self.mutationSequence + 1),
            phase: phase ?? self.phase,
            stage: stage ?? self.stage,
            findings: findings ?? self.findings,
            candidates: candidates ?? self.candidates,
            patches: patches ?? self.patches,
            events: events ?? self.events,
            config: config ?? self.config,
            scope: scope ?? self.scope,
            workspacePath: workspacePath ?? self.workspacePath,
            currentRound: currentRound ?? self.currentRound,
            activeWorkerCount: activeWorkerCount ?? self.activeWorkerCount,
            startedAt: startedAt ?? self.startedAt,
            completedAt: completedAt ?? self.completedAt,
            analysisCompletedAt: analysisCompletedAt ?? self.analysisCompletedAt,
            lastError: lastError ?? self.lastError,
            currentJobId: currentJobId ?? self.currentJobId,
            lastTestStatus: lastTestStatus ?? self.lastTestStatus,
            audit: audit ?? self.audit,
            outcome: outcome ?? self.outcome,
            verifiedFindings: verifiedFindings ?? self.verifiedFindings,
            phaseLedger: phaseLedger ?? self.phaseLedger,
            fileLedger: fileLedger ?? self.fileLedger,
            lastUpdatedAt: lastUpdatedAt
        )
    }
}

extension FindingStatus {
    public var isOpenState: Bool {
        switch self {
        case .open, .patchPreparing, .patchReady, .patchApplying, .patchFailed, .prOpened, .blocked:
            return true
        case .fixApplied, .patchApplied, .merged, .dismissed, .wontFix, .closed:
            return false
        }
    }

    public var isAppliedState: Bool {
        switch self {
        case .fixApplied, .patchApplied, .merged:
            return true
        case .open, .patchPreparing, .patchReady, .patchApplying, .patchFailed, .prOpened, .blocked, .dismissed, .wontFix, .closed:
            return false
        }
    }
}
