import Foundation

public enum VerifiedFindingsSessionSyncService {
    public static func sync(
        snapshot: CodeReviewSessionSnapshot,
        existingEnvelope: VerifiedFindingsSessionEnvelope? = nil,
        entryPoint: VerifiedFindingOriginEntryPoint = .reviewChat
    ) -> VerifiedFindingsSessionEnvelope {
        let findings = applyIdentityPolicy(to: buildBaseFindings(snapshot: snapshot, entryPoint: entryPoint))
        let evidences = buildEvidences(snapshot: snapshot, findings: findings)
        let reports = buildVerificationReports(snapshot: snapshot, findings: findings, evidences: evidences)
        let patches = buildPatchArtifacts(snapshot: snapshot)
        let revalidations = buildRevalidationReports(snapshot: snapshot)
        let run = buildRun(snapshot: snapshot, entryPoint: entryPoint)
        let canonicalSnapshot = VerifiedFindingsCanonicalSnapshot(
            runs: [run.id: run],
            findings: Dictionary(uniqueKeysWithValues: findings.map { ($0.id, $0) }),
            evidences: Dictionary(uniqueKeysWithValues: evidences.map { ($0.id, $0) }),
            verificationReports: Dictionary(uniqueKeysWithValues: reports.map { ($0.id, $0) }),
            patchArtifacts: Dictionary(uniqueKeysWithValues: patches.map { ($0.id, $0) }),
            revalidationReports: Dictionary(uniqueKeysWithValues: revalidations.map { ($0.id, $0) }),
            commandLog: existingEnvelope?.canonicalSnapshot.commandLog ?? [],
            eventLog: snapshot.events.enumerated().map { index, event in
                VerifiedPipelineEvent(
                    id: event.id,
                    runId: snapshot.sessionId,
                    entityId: event.metadata["finding_id"] ?? event.metadata["candidate_id"] ?? snapshot.sessionId,
                    entityType: event.metadata["patch_id"] == nil ? .finding : .patch,
                    eventType: event.type.rawValue,
                    payload: event.toPayload().merging(["sequence": String(index)]) { current, _ in current },
                    eventSchemaVersion: 1,
                    entitySchemaVersion: 1,
                    migrationHint: nil,
                    createdAt: event.timestamp
                )
            },
            traceLog: snapshot.events.map { $0.detail ?? $0.type.rawValue }
        )
        return VerifiedFindingsSessionEnvelope(
            sessionId: snapshot.sessionId,
            canonicalSnapshot: canonicalSnapshot,
            projectionSnapshot: VerifiedFindingsProjectionBuilder.build(from: canonicalSnapshot),
            lastUpdatedAt: snapshot.lastUpdatedAt
        )
    }

    static func buildBaseFindings(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint
    ) -> [VerifiedFinding] {
        var results = snapshot.findings.map { mapFinding($0, entryPoint: entryPoint) }
        let findingIds = Set(results.map(\.id))
        for candidate in snapshot.candidates where !findingIds.contains(candidate.id) {
            results.append(mapCandidate(candidate, entryPoint: entryPoint))
        }
        return results
    }

    static func applyIdentityPolicy(to findings: [VerifiedFinding]) -> [VerifiedFinding] {
        var output: [VerifiedFinding] = []
        for finding in findings.sorted(by: { $0.createdAt < $1.createdAt }) {
            if let match = FindingIdentityService.findDuplicate(candidate: finding, existing: output) {
                output.append(copying(
                    finding,
                    possibleDuplicateOf: [match.existingFindingId],
                    mergedIntoFindingId: match.isExactDuplicate ? match.existingFindingId : nil,
                    recurrenceGroupId: match.existingFindingId
                ))
            } else {
                output.append(finding)
            }
        }
        return output
    }
}
