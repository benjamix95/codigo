import Foundation

extension MCPSharedState {
    static func rustBuildCodeReviewIndex(
        snapshots: [CodeReviewSessionSnapshot]
    ) -> MCPSharedCodeReviewIndex? {
        let request = RustMCPIndexRequest(
            schemaVersion: 1,
            reviewSnapshots: snapshots.map(RustMCPSnapshotRecord.init(snapshot:))
        )
        guard let response: RustMCPIndexResponse = ReviewCoreBridge.call(
            functionName: "review_core_mcp_read_index",
            request: request
        ) else {
            return nil
        }
        return MCPSharedCodeReviewIndex(
            latestSessionId: response.latestSessionId,
            latestSessionIdByConversation: response.latestSessionIdByConversation,
            sessions: response.sessions.map(\.sharedRecord)
        )
    }
}

extension RustMCPSnapshotRecord {
    init(snapshot: CodeReviewSessionSnapshot) {
        self.init(
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
            startedAtReferenceSeconds: snapshot.startedAt?.timeIntervalSinceReferenceDate,
            updatedAtReferenceSeconds: snapshot.lastUpdatedAt.timeIntervalSinceReferenceDate,
            isActive: snapshot.isActive,
            findingIds: snapshot.findings.map(\.id),
            candidateIds: snapshot.candidates.map(\.id),
            patches: snapshot.patches.map { RustMCPPatchRecord(id: $0.id, findingId: $0.findingId, verifyStatus: $0.verifyStatus.rawValue, riskScore: $0.riskScore) }
        )
    }
}

extension RustMCPIndexSessionRecord {
    var sharedRecord: MCPSharedCodeReviewSessionRecord {
        MCPSharedCodeReviewSessionRecord(
            sessionId: sessionId,
            conversationId: conversationId,
            phase: phase,
            stage: stage,
            findingsCount: findingsCount,
            openFindingsCount: openFindingsCount,
            currentRound: currentRound,
            activeWorkerCount: activeWorkerCount,
            scopeType: scopeType,
            scopeRef: scopeRef,
            startedAt: startedAtReferenceSeconds.map { Date(timeIntervalSinceReferenceDate: $0) },
            updatedAt: Date(timeIntervalSinceReferenceDate: updatedAtReferenceSeconds),
            isActive: isActive
        )
    }
}
