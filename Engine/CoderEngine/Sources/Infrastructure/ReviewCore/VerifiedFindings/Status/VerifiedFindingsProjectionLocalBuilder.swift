import Foundation

enum VerifiedFindingsProjectionLocalBuilder {
    private static let cacheLock = NSLock()
    private static var cache: [ProjectionCacheKey: VerifiedFindingsProjectionSnapshot] = [:]

    static func build(
        from snapshot: VerifiedFindingsCanonicalSnapshot
    ) -> VerifiedFindingsProjectionSnapshot {
        let cacheKey = ProjectionCacheKey(snapshot: snapshot)
        cacheLock.lock()
        if let cached = cache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

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

        let projection = VerifiedFindingsProjectionSnapshot(
            candidateQueue: candidates.sorted { $0.id < $1.id },
            verifiedQueue: verified.sorted { $0.id < $1.id },
            duplicatesCount: items.filter { !$0.duplicateOf.isEmpty || $0.mergedIntoFindingId != nil }.count,
            staleCandidatesCount: candidates.filter { $0.staleStatus != .active }.count,
            traceSnippets: Array(snapshot.traceLog.suffix(20))
        )

        cacheLock.lock()
        cache[cacheKey] = projection
        if cache.count > 64 {
            let oldestKey = cache.keys.sorted { $0.sortKey < $1.sortKey }.first ?? cacheKey
            cache.removeValue(forKey: oldestKey)
        }
        cacheLock.unlock()
        return projection
    }
}

private struct ProjectionCacheKey: Hashable {
    let findingCount: Int
    let traceCount: Int
    let sortKey: String

    init(snapshot: VerifiedFindingsCanonicalSnapshot) {
        self.findingCount = snapshot.findings.count
        self.traceCount = snapshot.traceLog.count
        self.sortKey = snapshot.findings.values
            .sorted { $0.id < $1.id }
            .map {
                [
                    $0.id,
                    String($0.version),
                    $0.status.rawValue,
                    $0.staleStatus.rawValue,
                    $0.mergedIntoFindingId ?? "",
                    $0.possibleDuplicateOf.joined(separator: ","),
                ].joined(separator: "|")
            }
            .joined(separator: "||")
    }
}
