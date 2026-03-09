import Foundation

extension CodeReviewSessionSnapshot {
    public var verifiedFindingsProjection: VerifiedFindingsProjectionSnapshot {
        verifiedFindings?.projectionSnapshot
            ?? VerifiedFindingsSessionSyncService.sync(snapshot: self).projectionSnapshot
    }

    public var canonicalVerifiedFindingsSnapshot: VerifiedFindingsCanonicalSnapshot {
        verifiedFindings?.canonicalSnapshot
            ?? VerifiedFindingsSessionSyncService.sync(snapshot: self).canonicalSnapshot
    }
}
