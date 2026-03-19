import Foundation

extension CodeReviewSessionEvent {
    public static func findingAdded(
        findingId: String,
        severity: String,
        filePath: String
    ) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .findingAdded,
            detail: "[\(severity)] \(filePath)",
            metadata: ["finding_id": findingId, "severity": severity, "file_path": filePath]
        )
    }

    public static func findingDismissed(
        findingId: String,
        reason: String
    ) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .findingDismissed,
            detail: "Finding \(findingId) dismissed: \(reason)",
            metadata: ["finding_id": findingId, "reason": reason]
        )
    }
}

public enum ReviewPatchStatus: String, Sendable, Codable, CaseIterable {
    case draft
    case verified
    case applied
    case applyFailed = "apply_failed"
    case prOpened = "pr_opened"
    case merged
    case conflict
    case rolledBack = "rolled_back"
}

public enum ReviewPatchVerifyStatus: String, Sendable, Codable, CaseIterable {
    case pending
    case verified
    case failed
    case skipped
}

public enum ReviewPatchPRStatus: String, Sendable, Codable, CaseIterable {
    case notRequested = "not_requested"
    case ready
    case opened
    case failed
}

public enum ReviewPatchMergeStatus: String, Sendable, Codable, CaseIterable {
    case notRequested = "not_requested"
    case pending
    case merged
    case failed
    case blocked
}

public struct ReviewPatchArtifact: Sendable, Identifiable, Codable, Equatable {
    public let id: String
    public let findingId: String
    public let patchText: String
    public let diffPreview: String
    public let touchedFiles: [String]
    public let riskScore: Double
    public var rollbackRef: String?
    public var status: ReviewPatchStatus
    public var verifyStatus: ReviewPatchVerifyStatus
    public var prStatus: ReviewPatchPRStatus
    public var mergeStatus: ReviewPatchMergeStatus
    public var conflicts: [String]
    public var worktreePath: String?
    public var branchName: String?
    public var baseBranchName: String?
    public var prURL: String?
    public var verificationReport: String?
    public var validationRunId: String?
    public var validationStatus: ValidationStatus
    public var validationSummary: String?
    public var applyMessage: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        findingId: String,
        patchText: String,
        diffPreview: String,
        touchedFiles: [String],
        riskScore: Double = 0,
        rollbackRef: String? = nil,
        status: ReviewPatchStatus = .draft,
        verifyStatus: ReviewPatchVerifyStatus = .pending,
        prStatus: ReviewPatchPRStatus = .notRequested,
        mergeStatus: ReviewPatchMergeStatus = .notRequested,
        conflicts: [String] = [],
        worktreePath: String? = nil,
        branchName: String? = nil,
        baseBranchName: String? = nil,
        prURL: String? = nil,
        verificationReport: String? = nil,
        validationRunId: String? = nil,
        validationStatus: ValidationStatus = .pending,
        validationSummary: String? = nil,
        applyMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.findingId = findingId
        self.patchText = patchText
        self.diffPreview = diffPreview
        self.touchedFiles = touchedFiles
        self.riskScore = riskScore
        self.rollbackRef = rollbackRef
        self.status = status
        self.verifyStatus = verifyStatus
        self.prStatus = prStatus
        self.mergeStatus = mergeStatus
        self.conflicts = conflicts
        self.worktreePath = worktreePath
        self.branchName = branchName
        self.baseBranchName = baseBranchName
        self.prURL = prURL
        self.verificationReport = verificationReport
        self.validationRunId = validationRunId
        self.validationStatus = validationStatus
        self.validationSummary = validationSummary
        self.applyMessage = applyMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension CodeReviewSessionState {
    public func addCandidate(_ candidate: ReviewCandidate) {
        _ = applySessionAction(operation: "add_candidate") {
            $0.candidate = candidate
        }
    }

    public func addCandidates(_ newCandidates: [ReviewCandidate]) {
        guard !newCandidates.isEmpty else { return }
        _ = applySessionAction(operation: "add_candidates") {
            $0.candidates = newCandidates
        }
    }

    public func updateCandidateStatus(
        candidateId: String,
        status: ReviewCandidateStatus,
        method: String?,
        report: String?,
        falsePositiveReason: String? = nil
    ) -> Bool {
        applySessionAction(operation: "update_candidate_status") {
            $0.candidateId = candidateId
            $0.status = status
            $0.method = method
            $0.report = report
            $0.falsePositiveReason = falsePositiveReason
        }
    }

    public func promoteCandidateToFinding(candidateId: String) -> Bool {
        applySessionAction(operation: "promote_candidate_to_finding") {
            $0.candidateId = candidateId
        }
    }

    public func upsertPatch(_ patch: ReviewPatchArtifact) {
        _ = applySessionAction(operation: "upsert_patch") {
            $0.patch = patch
        }
    }

    public func patch(forFindingId findingId: String) -> ReviewPatchArtifact? {
        patches.first(where: { $0.findingId == findingId })
    }
}

extension CodeReviewSessionSnapshot {
    public func buildOutcomeSummary(summaryOverride: String? = nil) -> ReviewSessionOutcome {
        let verifiedFindings = findings.count
        let falsePositives = candidates.filter { $0.verificationStatus == .rejectedFalsePositive }.count
        let patchesReady = patches.filter { $0.status == .verified || $0.status == .draft }.count
        let patchesApplied = patches.filter { $0.status == .applied }.count
        let prsOpened = patches.filter { $0.prStatus == .opened || $0.status == .prOpened }.count
        let mergedPatches = patches.filter { $0.mergeStatus == .merged || $0.status == .merged }.count
        let conflictsDetected = patches.reduce(0) { $0 + $1.conflicts.count }
        let manualActionRequired = patches.contains {
            $0.status == .conflict || $0.mergeStatus == .blocked || $0.status == .applyFailed
        } || candidates.contains { $0.verificationStatus == .inconclusive }
        let summary = summaryOverride
            ?? "\(verifiedFindings) verified finding(s), \(falsePositives) false positive(s), \(patchesApplied) patch(es) applied."
        return ReviewSessionOutcome(
            summary: summary,
            verifiedFindings: verifiedFindings,
            falsePositives: falsePositives,
            patchesReady: patchesReady,
            patchesApplied: patchesApplied,
            prsOpened: prsOpened,
            mergedPatches: mergedPatches,
            conflictsDetected: conflictsDetected,
            manualActionRequired: manualActionRequired,
            testsStatus: lastTestStatus
        )
    }
}
