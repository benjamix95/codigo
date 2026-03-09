import Foundation

extension CodeReviewSessionSnapshot {
    public var verifiedFindingsProjection: VerifiedFindingsProjectionSnapshot {
        VerifiedFindingsProjectionBuilder.build(from: canonicalVerifiedFindingsSnapshot)
    }

    public var canonicalVerifiedFindingsSnapshot: VerifiedFindingsCanonicalSnapshot {
        let canonicalFindings = findings.reduce(into: [String: VerifiedFinding]()) { partialResult, finding in
            let domain: VerifiedFindingDomain = finding.origin == .securityAuditor || finding.category == .security
                ? .security
                : .bug
            let status = finding.verifiedAt != nil || finding.verificationReport != nil
                ? mapStatus(finding.status)
                : .candidate
            let fingerprint = FindingIdentityService.fingerprint(
                domain: domain,
                filePath: finding.filePath,
                category: finding.category.rawValue,
                title: finding.message,
                lineStart: finding.lineNumber,
                summary: finding.evidence ?? finding.message
            )
            partialResult[finding.id] = VerifiedFinding(
                id: finding.id,
                domain: domain,
                title: finding.message,
                summary: finding.evidence ?? finding.message,
                category: finding.category.rawValue,
                severity: mapSeverity(finding.severity),
                confidence: finding.confidence ?? 0.0,
                status: status,
                filePath: finding.filePath,
                lineStart: finding.lineNumber,
                lineEnd: finding.endLineNumber,
                evidenceIds: finding.evidence.map { _ in ["evidence-\(finding.id)"] } ?? [],
                verificationReportId: finding.verificationReport.map { _ in "verification-\(finding.id)" },
                patchId: finding.patchArtifactId,
                reproducibility: .partial,
                originEntryPoint: .reviewChat,
                lastCommandId: nil,
                staleStatus: .active,
                policyFlags: [],
                findingFingerprint: fingerprint
            )
        }
        return VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: canonicalFindings,
            evidences: [:],
            verificationReports: [:],
            patchArtifacts: [:],
            revalidationReports: [:],
            commandLog: [],
            eventLog: [],
            traceLog: events.map { $0.detail ?? $0.type.rawValue }
        )
    }

    private func mapStatus(_ status: FindingStatus) -> VerifiedFindingStatus {
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
        }
    }

    private func mapSeverity(_ severity: FindingSeverity) -> VerifiedFindingSeverity {
        switch severity {
        case .critical: return .critical
        case .warning: return .medium
        case .suggestion: return .low
        case .info: return .info
        }
    }
}
