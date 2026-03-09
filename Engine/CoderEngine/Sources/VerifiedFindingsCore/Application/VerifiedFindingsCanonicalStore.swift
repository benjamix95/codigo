import Foundation

public struct VerifiedFindingsCanonicalSnapshot: Sendable, Codable, Equatable {
    public let runs: [String: VerifiedPipelineRun]
    public let findings: [String: VerifiedFinding]
    public let evidences: [String: VerifiedEvidence]
    public let verificationReports: [String: VerifiedVerificationReport]
    public let patchArtifacts: [String: VerifiedPatchArtifact]
    public let revalidationReports: [String: VerifiedRevalidationReport]
    public let commandLog: [VerifiedCommandDeduplicationRecord]
    public let eventLog: [VerifiedPipelineEvent]
    public let traceLog: [String]
}

public actor VerifiedFindingsCanonicalStore {
    private var runs: [String: VerifiedPipelineRun] = [:]
    private var findings: [String: VerifiedFinding] = [:]
    private var evidences: [String: VerifiedEvidence] = [:]
    private var verificationReports: [String: VerifiedVerificationReport] = [:]
    private var patchArtifacts: [String: VerifiedPatchArtifact] = [:]
    private var revalidationReports: [String: VerifiedRevalidationReport] = [:]
    private var commandLog: [VerifiedCommandDeduplicationRecord] = []
    private var eventLog: [VerifiedPipelineEvent] = []
    private var traceLog: [String] = []

    public init() {}

    public func upsert(run: VerifiedPipelineRun) { runs[run.id] = run }
    public func upsert(finding: VerifiedFinding) { findings[finding.id] = finding }
    public func upsert(evidence: VerifiedEvidence) { evidences[evidence.id] = evidence }
    public func upsert(report: VerifiedVerificationReport) { verificationReports[report.id] = report }
    public func upsert(patch: VerifiedPatchArtifact) { patchArtifacts[patch.id] = patch }
    public func upsert(revalidation: VerifiedRevalidationReport) { revalidationReports[revalidation.id] = revalidation }
    public func append(commandRecord: VerifiedCommandDeduplicationRecord) { commandLog.append(commandRecord) }
    public func append(event: VerifiedPipelineEvent) { eventLog.append(event) }
    public func append(trace: String) { traceLog.append(trace) }

    public func snapshot() -> VerifiedFindingsCanonicalSnapshot {
        VerifiedFindingsCanonicalSnapshot(
            runs: runs,
            findings: findings,
            evidences: evidences,
            verificationReports: verificationReports,
            patchArtifacts: patchArtifacts,
            revalidationReports: revalidationReports,
            commandLog: commandLog,
            eventLog: eventLog,
            traceLog: traceLog
        )
    }
}
