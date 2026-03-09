import Foundation

extension CodeReviewSessionSnapshot {
    public var verifiedFindingsProjection: VerifiedFindingsProjectionSnapshot {
        VerifiedFindingsService.projection(snapshot: self)
    }

    public var canonicalVerifiedFindingsSnapshot: VerifiedFindingsCanonicalSnapshot {
        VerifiedFindingsService.canonicalSnapshot(snapshot: self)
    }
}
