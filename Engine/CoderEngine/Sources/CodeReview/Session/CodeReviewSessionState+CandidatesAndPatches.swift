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
        candidates.append(candidate)
        events.append(.candidateAdded(candidateId: candidate.id, filePath: candidate.filePath))
        notifyChange()
    }

    public func addCandidates(_ newCandidates: [ReviewCandidate]) {
        guard !newCandidates.isEmpty else { return }
        for candidate in newCandidates {
            candidates.append(candidate)
            events.append(.candidateAdded(candidateId: candidate.id, filePath: candidate.filePath))
        }
        notifyChange()
    }

    public func updateCandidateStatus(
        candidateId: String,
        status: ReviewCandidateStatus,
        method: String?,
        report: String?,
        falsePositiveReason: String? = nil
    ) -> Bool {
        guard let index = candidates.firstIndex(where: { $0.id == candidateId }) else {
            return false
        }
        candidates[index].verificationStatus = status
        candidates[index].verificationMethod = method
        candidates[index].verificationReport = report
        candidates[index].falsePositiveReason = falsePositiveReason
        candidates[index].verifiedAt = status == .verified ? Date() : nil
        switch status {
        case .verified:
            events.append(.candidateVerified(candidateId: candidateId))
        case .rejectedFalsePositive:
            events.append(.candidateRejected(candidateId: candidateId, reason: falsePositiveReason ?? "false_positive"))
        default:
            break
        }
        notifyChange()
        return true
    }

    public func promoteCandidateToFinding(candidateId: String) -> Bool {
        guard let candidate = candidates.first(where: { $0.id == candidateId }),
              candidate.verificationStatus == .verified
        else {
            return false
        }
        guard !findings.contains(where: { $0.id == candidateId }) else {
            return true
        }
        findings.append(.fromCandidate(candidate))
        events.append(.findingAdded(
            findingId: candidate.id,
            severity: candidate.severity.rawValue,
            filePath: candidate.filePath
        ))
        notifyChange()
        return true
    }

    public func upsertPatch(_ patch: ReviewPatchArtifact) {
        if let index = patches.firstIndex(where: { $0.id == patch.id || $0.findingId == patch.findingId }) {
            patches[index] = patch
        } else {
            patches.append(patch)
        }

        if let findingIndex = findings.firstIndex(where: { $0.id == patch.findingId }) {
            findings[findingIndex].patchArtifactId = patch.id
            findings[findingIndex].status = switch patch.status {
            case .draft: .patchPreparing
            case .verified: .patchReady
            case .applied: .patchApplied
            case .applyFailed: .patchFailed
            case .prOpened: .prOpened
            case .merged: .merged
            case .conflict: .blocked
            case .rolledBack: .blocked
            }
        }

        switch patch.status {
        case .draft:
            events.append(.patchPrepared(patchId: patch.id, findingId: patch.findingId))
        case .verified:
            events.append(CodeReviewSessionEvent(
                type: .patchVerified,
                detail: "Patch \(patch.id) verified",
                metadata: ["patch_id": patch.id, "finding_id": patch.findingId]
            ))
        case .applyFailed:
            events.append(CodeReviewSessionEvent(
                type: .patchApplyFailed,
                detail: patch.applyMessage ?? "Patch apply failed",
                metadata: ["patch_id": patch.id, "finding_id": patch.findingId]
            ))
        case .prOpened:
            events.append(CodeReviewSessionEvent(
                type: .prOpened,
                detail: patch.prURL ?? "Pull request opened",
                metadata: ["patch_id": patch.id, "finding_id": patch.findingId]
            ))
        case .merged:
            events.append(CodeReviewSessionEvent(
                type: .prMerged,
                detail: patch.prURL ?? "Patch merged",
                metadata: ["patch_id": patch.id, "finding_id": patch.findingId]
            ))
        case .conflict:
            events.append(CodeReviewSessionEvent(
                type: .conflictDetected,
                detail: patch.conflicts.joined(separator: ", "),
                metadata: ["patch_id": patch.id, "finding_id": patch.findingId]
            ))
        case .applied, .rolledBack:
            events.append(.findingFixApplied(findingId: patch.findingId))
        }

        outcome = snapshot().buildOutcomeSummary()
        notifyChange()
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
