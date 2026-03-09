import Foundation

extension CodeReviewSessionSnapshot {
    public var verifiedFindingsProjection: VerifiedFindingsProjectionSnapshot {
        VerifiedFindingsCheckpointService.resolveEnvelope(snapshot: self).envelope.projectionSnapshot
    }

    public var canonicalVerifiedFindingsSnapshot: VerifiedFindingsCanonicalSnapshot {
        VerifiedFindingsCheckpointService.resolveEnvelope(snapshot: self).envelope.canonicalSnapshot
    }
}
