import Foundation

extension MCPSharedState {
    static func rebuiltCodeReviewIndexUnsafe() -> MCPSharedCodeReviewIndex {
        buildCodeReviewIndex(snapshots: allCodeReviewSnapshotsUnsafe())
    }

    static func sortCodeReviewSnapshots(
        _ lhs: CodeReviewSessionSnapshot,
        _ rhs: CodeReviewSessionSnapshot
    ) -> Bool {
        if lhs.lastUpdatedAt != rhs.lastUpdatedAt {
            return lhs.lastUpdatedAt > rhs.lastUpdatedAt
        }
        if lhs.mutationSequence != rhs.mutationSequence {
            return lhs.mutationSequence > rhs.mutationSequence
        }
        return lhs.sessionId > rhs.sessionId
    }

    static func shouldSkipCodeReviewSnapshotWrite(
        current: CodeReviewSessionSnapshot,
        incoming: CodeReviewSessionSnapshot
    ) -> Bool {
        if incoming.mutationSequence != current.mutationSequence {
            return incoming.mutationSequence < current.mutationSequence
        }
        return incoming.lastUpdatedAt < current.lastUpdatedAt
    }
}
