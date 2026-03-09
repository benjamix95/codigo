import Foundation

public enum VerifiedFindingAdmissionPolicy {
    public static func canPromoteFinding(
        _ finding: VerifiedFinding,
        verificationReports: [VerifiedVerificationReport],
        evidences: [VerifiedEvidence],
        minimumConfidence: Double = 0.80
    ) -> Bool {
        guard finding.confidence >= minimumConfidence else { return false }
        guard verificationReports.contains(where: { report in
            report.verdict == .verified && report.confidence >= minimumConfidence
        }) else {
            return false
        }
        return evidences.contains(where: hasValidProvenance)
    }

    public static func requiresManualReview(
        _ report: VerifiedVerificationReport
    ) -> Bool {
        report.verdict == .needsManualReview || report.errorCategory == .unsupportedVerificationPath
    }

    private static func hasValidProvenance(_ evidence: VerifiedEvidence) -> Bool {
        !evidence.originTool.isEmpty &&
        !evidence.originCommandId.isEmpty &&
        !evidence.originRunId.isEmpty &&
        !evidence.originStep.isEmpty &&
        !evidence.hashOrFingerprint.isEmpty
    }
}
