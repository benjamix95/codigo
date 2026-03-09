import Foundation

extension VerifiedFindingsSessionSyncService {
    static func mapFinding(
        _ finding: CodeReviewFinding,
        patch: ReviewPatchArtifact?,
        entryPoint: VerifiedFindingOriginEntryPoint
    ) -> VerifiedFinding {
        let domain: VerifiedFindingDomain = finding.origin == .securityAuditor || finding.category == .security ? .security : .bug
        let derivedStatus = derivedStatus(for: finding, patch: patch)
        return VerifiedFinding(
            id: finding.id,
            domain: domain,
            title: finding.message,
            summary: finding.evidence ?? finding.message,
            category: finding.category.rawValue,
            severity: mapSeverity(finding.severity),
            confidence: finding.confidence ?? 0.0,
            status: derivedStatus,
            filePath: finding.filePath,
            lineStart: finding.lineNumber,
            lineEnd: finding.endLineNumber,
            evidenceIds: finding.evidence.map { _ in ["evidence-\(finding.id)"] } ?? [],
            verificationReportId: finding.verificationReport.map { _ in "verification-\(finding.id)" },
            patchId: finding.patchArtifactId,
            revalidationReportId: patch?.validationRunId != nil ? "revalidation-\(patch?.id ?? finding.id)" : nil,
            rootCause: finding.verificationReport,
            impact: finding.message,
            exploitability: nil,
            reproducibility: finding.verificationReport == nil ? .none : .partial,
            originEntryPoint: entryPoint,
            lastCommandId: nil,
            staleStatus: .active,
            closedReason: closedReason(for: finding.status),
            policyFlags: [],
            findingFingerprint: FindingIdentityService.fingerprint(
                domain: domain,
                filePath: finding.filePath,
                category: finding.category.rawValue,
                title: finding.message,
                lineStart: finding.lineNumber,
                summary: finding.evidence ?? finding.message
            ),
            createdAt: finding.createdAt,
            updatedAt: finding.verifiedAt ?? finding.createdAt
        )
    }

    static func mapCandidate(_ candidate: ReviewCandidate, entryPoint: VerifiedFindingOriginEntryPoint) -> VerifiedFinding {
        let domain: VerifiedFindingDomain = candidate.origin == .securityAuditor || candidate.category == .security ? .security : .bug
        return VerifiedFinding(
            id: candidate.id,
            domain: domain,
            title: candidate.message,
            summary: candidate.evidence ?? candidate.message,
            category: candidate.category.rawValue,
            severity: mapSeverity(candidate.severity),
            confidence: candidate.confidence ?? 0.0,
            status: mapCandidateStatus(candidate.verificationStatus),
            filePath: candidate.filePath,
            lineStart: candidate.lineNumber,
            lineEnd: candidate.endLineNumber,
            verificationReportId: candidate.verificationReport.map { _ in "verification-\(candidate.id)" },
            rootCause: candidate.verificationReport,
            reproducibility: candidate.reproOrReasoning == nil ? .none : .partial,
            originEntryPoint: entryPoint,
            lastCommandId: nil,
            staleStatus: .active,
            policyFlags: [],
            findingFingerprint: FindingIdentityService.fingerprint(
                domain: domain,
                filePath: candidate.filePath,
                category: candidate.category.rawValue,
                title: candidate.message,
                lineStart: candidate.lineNumber,
                summary: candidate.evidence ?? candidate.message
            ),
            createdAt: candidate.createdAt,
            updatedAt: candidate.verifiedAt ?? candidate.createdAt
        )
    }

    static func mapSeverity(_ severity: FindingSeverity) -> VerifiedFindingSeverity {
        switch severity {
        case .critical: return .critical
        case .warning: return .medium
        case .suggestion: return .low
        case .info: return .info
        }
    }

    static func mapFindingStatus(_ status: FindingStatus) -> VerifiedFindingStatus {
        switch status {
        case .open: return .verified
        case .fixApplied, .patchApplied: return .patchApplied
        case .patchPreparing: return .patchPreparing
        case .patchReady: return .patchPrepared
        case .patchApplying: return .patchReviewed
        case .patchFailed: return .fixFailed
        case .prOpened, .merged: return .closed
        case .blocked: return .needsManualReview
        case .dismissed, .wontFix: return .rejected
        case .closed: return .closed
        }
    }

    static func derivedStatus(
        for finding: CodeReviewFinding,
        patch: ReviewPatchArtifact?
    ) -> VerifiedFindingStatus {
        guard let patch else { return mapFindingStatus(finding.status) }
        if patch.status == .applied {
            switch patch.validationStatus {
            case .passed:
                return .fixedVerified
            case .failed:
                return .fixFailed
            case .pending:
                return .patchApplied
            }
        }
        if patch.status == .rolledBack {
            return .rollbackApplied
        }
        return mapFindingStatus(finding.status)
    }

    static func mapCandidateStatus(_ status: ReviewCandidateStatus) -> VerifiedFindingStatus {
        switch status {
        case .new: return .candidate
        case .verifying: return .verifying
        case .verified: return .verified
        case .rejectedFalsePositive: return .rejected
        case .inconclusive: return .needsManualReview
        }
    }

    static func verificationVerdict(for status: VerifiedFindingStatus) -> VerificationVerdict {
        switch status {
        case .verified, .patchPreparing, .patchPrepared, .patchReviewed, .patchApplied, .revalidating, .fixedVerified, .fixFailed, .rollbackApplied, .closed:
            return .verified
        case .rejected:
            return .rejected
        case .needsManualReview:
            return .needsManualReview
        case .candidate, .verifying:
            return .inconclusive
        }
    }

    static func mapApplyStatus(_ status: ReviewPatchStatus) -> VerifiedPatchApplyStatus {
        switch status {
        case .draft, .verified, .prOpened, .merged, .conflict:
            return .notApplied
        case .applied:
            return .applied
        case .applyFailed:
            return .failed
        case .rolledBack:
            return .rolledBack
        }
    }

    static func mapRunStatus(_ phase: ReviewSessionPhase) -> VerifiedRunStatus {
        switch phase {
        case .idle: return .queued
        case .analyzing, .fixing, .testing, .reReviewing: return .running
        case .completed: return .completed
        case .failed: return .failed
        }
    }

    static func closedReason(for status: FindingStatus) -> String? {
        switch status {
        case .dismissed: return "dismissed"
        case .wontFix: return "wont_fix"
        case .merged: return "merged"
        case .prOpened: return "pr_opened"
        case .closed: return "closed"
        default: return nil
        }
    }

    static func copying(
        _ finding: VerifiedFinding,
        possibleDuplicateOf: [String],
        mergedIntoFindingId: String?,
        recurrenceGroupId: String?
    ) -> VerifiedFinding {
        VerifiedFinding(
            id: finding.id,
            domain: finding.domain,
            title: finding.title,
            summary: finding.summary,
            category: finding.category,
            severity: finding.severity,
            confidence: finding.confidence,
            status: finding.status,
            filePath: finding.filePath,
            lineStart: finding.lineStart,
            lineEnd: finding.lineEnd,
            ruleId: finding.ruleId,
            evidenceIds: finding.evidenceIds,
            verificationReportId: finding.verificationReportId,
            patchId: finding.patchId,
            revalidationReportId: finding.revalidationReportId,
            rootCause: finding.rootCause,
            impact: finding.impact,
            exploitability: finding.exploitability,
            reproducibility: finding.reproducibility,
            version: finding.version,
            originEntryPoint: finding.originEntryPoint,
            lastCommandId: finding.lastCommandId,
            staleStatus: finding.staleStatus,
            closedReason: finding.closedReason,
            policyFlags: finding.policyFlags,
            findingFingerprint: finding.findingFingerprint,
            identityVersion: finding.identityVersion,
            possibleDuplicateOf: possibleDuplicateOf,
            mergedIntoFindingId: mergedIntoFindingId,
            recurrenceGroupId: recurrenceGroupId,
            createdAt: finding.createdAt,
            updatedAt: finding.updatedAt
        )
    }
}
