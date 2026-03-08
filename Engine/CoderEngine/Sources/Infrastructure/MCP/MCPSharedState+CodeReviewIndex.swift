import Foundation

extension MCPSharedState {
    static func rebuiltCodeReviewIndexUnsafe() -> MCPSharedCodeReviewIndex {
        let snapshots = allCodeReviewSnapshotsUnsafe().sorted(by: sortCodeReviewSnapshots)
        let records = snapshots.map { snapshot in
            MCPSharedCodeReviewSessionRecord(
                sessionId: snapshot.sessionId,
                conversationId: snapshot.conversationId?.uuidString.lowercased(),
                phase: snapshot.phase.rawValue,
                stage: snapshot.stage.rawValue,
                findingsCount: snapshot.findings.count,
                openFindingsCount: snapshot.openFindings.count,
                currentRound: snapshot.currentRound,
                activeWorkerCount: snapshot.activeWorkerCount,
                scopeType: snapshot.scope?.type.rawValue,
                scopeRef: snapshot.scope?.ref,
                startedAt: snapshot.startedAt,
                updatedAt: snapshot.lastUpdatedAt,
                isActive: snapshot.isActive
            )
        }

        var latestSessionIdByConversation: [String: String] = [:]
        for snapshot in snapshots {
            guard let conversationId = snapshot.conversationId?.uuidString.lowercased(),
                  latestSessionIdByConversation[conversationId] == nil else {
                continue
            }
            latestSessionIdByConversation[conversationId] = snapshot.sessionId
        }

        return MCPSharedCodeReviewIndex(
            latestSessionId: snapshots.first?.sessionId,
            latestSessionIdByConversation: latestSessionIdByConversation,
            sessions: records
        )
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
