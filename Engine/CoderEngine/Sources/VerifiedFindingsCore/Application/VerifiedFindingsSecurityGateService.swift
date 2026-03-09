import Foundation

public struct VerifiedFindingsSecurityGateReport: Sendable, Codable, Equatable {
    public let ready: Bool
    public let canonicalProjectionMismatchCount: Int
    public let undetectedDuplicateCount: Int
    public let findingsMissingEvidenceCount: Int
    public let findingsMissingVerificationCount: Int
    public let rollbackCoverageCount: Int
    public let rollbackEligibleCount: Int
    public let applyRevalidateSuccessRate: Double
    public let knownCriticalRaceCount: Int
    public let summary: String
}

public enum VerifiedFindingsSecurityGateService {
    public static func evaluate(
        envelope: VerifiedFindingsSessionEnvelope
    ) -> VerifiedFindingsSecurityGateReport {
        let canonical = envelope.canonicalSnapshot
        let rebuiltProjection = VerifiedFindingsProjectionBuilder.build(from: canonical)
        let mismatchCount = rebuiltProjection == envelope.projectionSnapshot ? 0 : 1

        let findings = Array(canonical.findings.values)
        let verificationReportsByFinding = Dictionary(grouping: canonical.verificationReports.values, by: \.findingId)
        let evidencesByFinding = Dictionary(grouping: canonical.evidences.values, by: \.findingId)
        let undetectedDuplicateCount = countUndetectedDuplicates(findings)
        let findingsMissingEvidenceCount = findings.filter {
            guard $0.status == .verified || $0.status == .fixedVerified else { return false }
            return (evidencesByFinding[$0.id] ?? []).isEmpty
        }.count
        let findingsMissingVerificationCount = findings.filter {
            guard $0.status == .verified || $0.status == .fixedVerified else { return false }
            return (verificationReportsByFinding[$0.id] ?? []).isEmpty
        }.count

        let bugPatches = canonical.patchArtifacts.values.filter { patch in
            canonical.findings[patch.findingId]?.domain == .bug
        }
        let rollbackCoverageCount = bugPatches.filter(\.rollbackAvailable).count
        let rollbackEligibleCount = bugPatches.count
        let bugRevalidations = canonical.revalidationReports.values.filter { report in
            canonical.findings[report.findingId]?.domain == .bug
        }
        let successfulBugRevalidations = bugRevalidations.filter { $0.verdict == .fixedVerified }.count
        let applyRevalidateSuccessRate = bugRevalidations.isEmpty
            ? 1.0
            : Double(successfulBugRevalidations) / Double(bugRevalidations.count)

        let ready = mismatchCount == 0
            && undetectedDuplicateCount == 0
            && findingsMissingEvidenceCount == 0
            && findingsMissingVerificationCount == 0
            && (rollbackEligibleCount == 0 || rollbackCoverageCount == rollbackEligibleCount)
            && applyRevalidateSuccessRate >= 0.90

        return VerifiedFindingsSecurityGateReport(
            ready: ready,
            canonicalProjectionMismatchCount: mismatchCount,
            undetectedDuplicateCount: undetectedDuplicateCount,
            findingsMissingEvidenceCount: findingsMissingEvidenceCount,
            findingsMissingVerificationCount: findingsMissingVerificationCount,
            rollbackCoverageCount: rollbackCoverageCount,
            rollbackEligibleCount: rollbackEligibleCount,
            applyRevalidateSuccessRate: applyRevalidateSuccessRate,
            knownCriticalRaceCount: 0,
            summary: summary(
                ready: ready,
                mismatchCount: mismatchCount,
                undetectedDuplicateCount: undetectedDuplicateCount,
                findingsMissingEvidenceCount: findingsMissingEvidenceCount,
                findingsMissingVerificationCount: findingsMissingVerificationCount,
                rollbackCoverageCount: rollbackCoverageCount,
                rollbackEligibleCount: rollbackEligibleCount,
                applyRevalidateSuccessRate: applyRevalidateSuccessRate
            )
        )
    }

    private static func countUndetectedDuplicates(_ findings: [VerifiedFinding]) -> Int {
        let grouped = Dictionary(grouping: findings, by: \.findingFingerprint)
        return grouped.values.reduce(0) { result, group in
            guard group.count > 1 else { return result }
            let unresolved = group.filter {
                $0.possibleDuplicateOf.isEmpty && $0.mergedIntoFindingId == nil && $0.recurrenceGroupId == nil
            }
            return result + unresolved.count
        }
    }

    private static func summary(
        ready: Bool,
        mismatchCount: Int,
        undetectedDuplicateCount: Int,
        findingsMissingEvidenceCount: Int,
        findingsMissingVerificationCount: Int,
        rollbackCoverageCount: Int,
        rollbackEligibleCount: Int,
        applyRevalidateSuccessRate: Double
    ) -> String {
        let readiness = ready ? "ready" : "blocked"
        let rate = String(format: "%.0f%%", applyRevalidateSuccessRate * 100)
        return "security_gate=\(readiness), mismatches=\(mismatchCount), undetected_duplicates=\(undetectedDuplicateCount), missing_evidence=\(findingsMissingEvidenceCount), missing_verification=\(findingsMissingVerificationCount), rollback=\(rollbackCoverageCount)/\(rollbackEligibleCount), apply_revalidate_success=\(rate)"
    }
}
