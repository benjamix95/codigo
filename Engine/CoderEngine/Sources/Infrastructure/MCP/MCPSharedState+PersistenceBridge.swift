import Foundation

extension MCPSharedState {
    static func persistenceStoreIfAvailable() -> PostgresPersistenceStore? {
        guard PersistenceFeatureFlags.isEnabled else { return nil }
        do {
            _ = try PersistenceBootstrapService.shared.bootstrapIfNeeded()
            return .shared
        } catch {
            #if DEBUG
            print("[Persistence] Falling back to legacy storage: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    static func readVerifiedFindingsEnvelopeFromPersistence(
        sessionId: String
    ) -> VerifiedFindingsSessionEnvelope? {
        guard let store = persistenceStoreIfAvailable() else { return nil }
        return try? store.readVerifiedFindingsEnvelope(sessionId: sessionId)
    }

    static func readVerifiedFindingsCheckpointFromPersistence(
        sessionId: String
    ) -> MCPSharedVerifiedFindingsCheckpoint? {
        guard let envelope = readVerifiedFindingsEnvelopeFromPersistence(sessionId: sessionId) else {
            return nil
        }
        return MCPSharedVerifiedFindingsCheckpoint(
            sessionId: envelope.sessionId,
            eventSchemaVersion: envelope.eventSchemaVersion,
            projectionSchemaVersion: envelope.projectionSchemaVersion,
            entitySchemaVersion: envelope.entitySchemaVersion,
            checkpointedAt: envelope.lastUpdatedAt,
            findingCount: envelope.canonicalSnapshot.findings.count,
            eventCount: envelope.canonicalSnapshot.eventLog.count,
            traceCount: envelope.canonicalSnapshot.traceLog.count
        )
    }

    static func buildCodeReviewIndex(
        snapshots: [CodeReviewSessionSnapshot]
    ) -> MCPSharedCodeReviewIndex {
        let sortedSnapshots = snapshots.sorted(by: sortCodeReviewSnapshots)
        let records = sortedSnapshots.map { snapshot in
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
        for snapshot in sortedSnapshots {
            guard let conversationId = snapshot.conversationId?.uuidString.lowercased(),
                  latestSessionIdByConversation[conversationId] == nil else {
                continue
            }
            latestSessionIdByConversation[conversationId] = snapshot.sessionId
        }

        return MCPSharedCodeReviewIndex(
            latestSessionId: sortedSnapshots.first?.sessionId,
            latestSessionIdByConversation: latestSessionIdByConversation,
            sessions: records
        )
    }

    static func buildPlanSnapshotJSONObject(
        snapshot: MCPSharedPlanSnapshot,
        latestConversationId: String?,
        includeHistory: Bool,
        history: [MCPSharedPlanSnapshot]
    ) -> [String: Any]? {
        guard var latestObject = jsonObject(snapshot) else { return nil }
        latestObject["conversation_id"] = snapshot.conversationId
        latestObject["snapshot_id"] = snapshot.snapshotId

        var output: [String: Any] = [
            "version": 1,
            "latest_conversation_id": latestConversationId as Any,
            "conversation_id": snapshot.conversationId,
            "snapshot": latestObject,
        ]

        if includeHistory {
            output["history"] = jsonArray(history) ?? []
        }
        return output
    }

    static func buildPlanDiff(
        from: MCPSharedPlanSnapshot,
        to: MCPSharedPlanSnapshot
    ) -> [String: Any]? {
        let fromById = Dictionary(from.steps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let toById = Dictionary(to.steps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let added = to.steps.filter { fromById[$0.id] == nil }
        let removed = from.steps.filter { toById[$0.id] == nil }
        let statusChanges = to.steps.compactMap { step -> MCPSharedPlanStatusChange? in
            guard let previous = fromById[step.id], previous.status != step.status else { return nil }
            return MCPSharedPlanStatusChange(
                stepId: step.id,
                title: step.title,
                fromStatus: previous.status,
                toStatus: step.status
            )
        }

        let diff = MCPSharedPlanDiffResult(
            fromSnapshotId: from.snapshotId,
            toSnapshotId: to.snapshotId,
            goalChanged: from.goal != to.goal,
            addedSteps: added,
            removedSteps: removed,
            statusChanges: statusChanges
        )
        guard let raw = jsonObject(diff) else { return nil }
        return [
            "from_snapshot_id": diff.fromSnapshotId,
            "to_snapshot_id": diff.toSnapshotId,
            "goal_changed": diff.goalChanged,
            "added_steps": raw["addedSteps"] ?? [],
            "removed_steps": raw["removedSteps"] ?? [],
            "status_changes": raw["statusChanges"] ?? [],
        ]
    }
}
