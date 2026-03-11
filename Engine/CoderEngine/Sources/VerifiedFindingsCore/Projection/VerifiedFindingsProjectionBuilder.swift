import Foundation

public enum VerifiedFindingsProjectionBuilder {
    public static func build(
        from snapshot: VerifiedFindingsCanonicalSnapshot
    ) -> VerifiedFindingsProjectionSnapshot {
        if let bridged = buildWithRust(from: snapshot) {
            return bridged
        }
        let items = snapshot.findings.values.map { finding in
            VerifiedFindingListItemProjection(
                id: finding.id,
                title: finding.title,
                domain: finding.domain,
                status: finding.status,
                staleStatus: finding.staleStatus,
                severity: finding.severity,
                filePath: finding.filePath,
                lineStart: finding.lineStart,
                duplicateOf: finding.possibleDuplicateOf,
                mergedIntoFindingId: finding.mergedIntoFindingId,
                recurrenceGroupId: finding.recurrenceGroupId
            )
        }
        let candidates = items.filter { $0.status == .candidate || $0.status == .verifying }
        let verified = items.filter {
            switch $0.status {
            case .verified, .patchPreparing, .patchPrepared, .patchReviewed, .patchApplied, .revalidating, .fixedVerified, .fixFailed, .rollbackApplied, .closed:
                return true
            case .candidate, .verifying, .rejected, .needsManualReview:
                return false
            }
        }
        return VerifiedFindingsProjectionSnapshot(
            candidateQueue: candidates.sorted { $0.id < $1.id },
            verifiedQueue: verified.sorted { $0.id < $1.id },
            duplicatesCount: items.filter { !$0.duplicateOf.isEmpty || $0.mergedIntoFindingId != nil }.count,
            staleCandidatesCount: candidates.filter { $0.staleStatus != .active }.count,
            traceSnippets: Array(snapshot.traceLog.suffix(20))
        )
    }

    private static func buildWithRust(
        from snapshot: VerifiedFindingsCanonicalSnapshot
    ) -> VerifiedFindingsProjectionSnapshot? {
        let request = ReviewCoreProjectionRequest(
            schemaVersion: 1,
            findings: Array(snapshot.findings.values),
            traceLog: snapshot.traceLog
        )
        let response: ReviewCoreProjectionBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_build_projection",
            request: request
        )
        return response?.projection
    }
}

private struct ReviewCoreProjectionRequest: Encodable {
    let schemaVersion: Int
    let findings: [VerifiedFinding]
    let traceLog: [String]
}

private struct ReviewCoreProjectionBridgeResponse: Decodable {
    let projection: VerifiedFindingsProjectionSnapshot?
}
