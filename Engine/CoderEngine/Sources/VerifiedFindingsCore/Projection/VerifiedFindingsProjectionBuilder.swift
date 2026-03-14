import Foundation

public struct VerifiedFindingListItemProjection: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let domain: VerifiedFindingDomain
    public let status: VerifiedFindingStatus
    public let staleStatus: VerifiedFindingStaleStatus
    public let severity: VerifiedFindingSeverity
    public let filePath: String
    public let lineStart: Int?
    public let duplicateOf: [String]
    public let mergedIntoFindingId: String?
    public let recurrenceGroupId: String?

    public init(
        id: String,
        title: String,
        domain: VerifiedFindingDomain,
        status: VerifiedFindingStatus,
        staleStatus: VerifiedFindingStaleStatus,
        severity: VerifiedFindingSeverity,
        filePath: String,
        lineStart: Int?,
        duplicateOf: [String],
        mergedIntoFindingId: String?,
        recurrenceGroupId: String?
    ) {
        self.id = id
        self.title = title
        self.domain = domain
        self.status = status
        self.staleStatus = staleStatus
        self.severity = severity
        self.filePath = filePath
        self.lineStart = lineStart
        self.duplicateOf = duplicateOf
        self.mergedIntoFindingId = mergedIntoFindingId
        self.recurrenceGroupId = recurrenceGroupId
    }
}

public struct VerifiedFindingsProjectionSnapshot: Sendable, Codable, Equatable {
    public let candidateQueue: [VerifiedFindingListItemProjection]
    public let verifiedQueue: [VerifiedFindingListItemProjection]
    public let duplicatesCount: Int
    public let staleCandidatesCount: Int
    public let traceSnippets: [String]

    public init(
        candidateQueue: [VerifiedFindingListItemProjection],
        verifiedQueue: [VerifiedFindingListItemProjection],
        duplicatesCount: Int,
        staleCandidatesCount: Int,
        traceSnippets: [String]
    ) {
        self.candidateQueue = candidateQueue
        self.verifiedQueue = verifiedQueue
        self.duplicatesCount = duplicatesCount
        self.staleCandidatesCount = staleCandidatesCount
        self.traceSnippets = traceSnippets
    }
}

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
