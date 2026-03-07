import CoderEngine
import Foundation

extension CodigoApp {
    @MainActor
    func persistLiveReviewState(
        _ state: CodeReviewSessionState,
        conversationId: UUID?
    ) async {
        let snapshot = await state.snapshot()
        await ReviewSessionRegistry.shared.recordSnapshot(snapshot)
        taskActivityStore.ingestCodeReviewSnapshot(
            snapshot,
            conversationId: conversationId ?? snapshot.conversationId
        )
    }

    @MainActor
    func applyReviewMutation(
        _ command: MCPSharedCodeReviewCommand,
        apply: @escaping (CodeReviewSessionState, [String: String]) async -> Bool
    ) async -> (success: Bool, message: String) {
        guard let sessionId = command.sessionId else {
            return (false, "Missing session_id")
        }
        if let liveState = await ReviewSessionRegistry.shared.state(sessionId: sessionId) {
            let succeeded = await apply(liveState, command.payload)
            if succeeded {
                await persistLiveReviewState(
                    liveState,
                    conversationId: command.conversationId.flatMap(UUID.init(uuidString:))
                )
            }
            return succeeded
                ? (true, "Command applied to live session")
                : (false, "Unable to update the requested finding")
        }

        return await persistReviewSnapshotMutation(sessionId: sessionId) { snapshot in
            mutateReviewSnapshot(snapshot: snapshot, command: command)
        }
    }

    @MainActor
    func persistReviewSnapshotMutation(
        sessionId: String,
        mutate: (CodeReviewSessionSnapshot) -> CodeReviewSessionSnapshot?
    ) async -> (success: Bool, message: String) {
        guard let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId),
              let updated = mutate(snapshot) else {
            return (false, "Review session not found")
        }
        MCPSharedState.writeCodeReviewSnapshot(updated)
        taskActivityStore.ingestCodeReviewSnapshot(
            updated,
            conversationId: updated.conversationId
        )
        return (true, "Snapshot updated")
    }

    func mutateReviewSnapshot(
        snapshot: CodeReviewSessionSnapshot,
        command: MCPSharedCodeReviewCommand
    ) -> CodeReviewSessionSnapshot? {
        var findings = snapshot.findings
        var events = snapshot.events
        let updatedAt = Date()

        switch command.action {
        case "apply_fix":
            guard let findingId = command.payload["finding_id"],
                  let index = findings.firstIndex(where: { $0.id == findingId }) else {
                return nil
            }
            findings[index].status = .fixApplied
            events.append(.findingFixApplied(findingId: findingId))
        case "dismiss":
            guard let findingId = command.payload["finding_id"],
                  let index = findings.firstIndex(where: { $0.id == findingId }) else {
                return nil
            }
            let reason = command.payload["reason"] ?? "dismissed"
            findings[index].status = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == FindingStatus.wontFix.rawValue
                ? .wontFix
                : .dismissed
            events.append(.findingDismissed(findingId: findingId, reason: reason))
        case "comment":
            guard let findingId = command.payload["finding_id"],
                  let content = command.payload["content"],
                  let index = findings.firstIndex(where: { $0.id == findingId }) else {
                return nil
            }
            findings[index].comments.append(
                FindingComment(author: command.payload["author"] ?? "agent", content: content)
            )
            events.append(CodeReviewSessionEvent(
                type: .findingCommented,
                detail: "Comment added from command bus",
                metadata: ["finding_id": findingId]
            ))
        default:
            return nil
        }

        return CodeReviewSessionSnapshot(
            sessionId: snapshot.sessionId,
            conversationId: snapshot.conversationId,
            phase: snapshot.phase,
            stage: snapshot.stage,
            findings: findings,
            events: events,
            config: snapshot.config,
            scope: snapshot.scope,
            workspacePath: snapshot.workspacePath,
            currentRound: snapshot.currentRound,
            activeWorkerCount: snapshot.activeWorkerCount,
            startedAt: snapshot.startedAt,
            completedAt: snapshot.completedAt,
            analysisCompletedAt: snapshot.analysisCompletedAt,
            lastError: snapshot.lastError,
            currentJobId: snapshot.currentJobId,
            lastTestStatus: snapshot.lastTestStatus,
            lastUpdatedAt: updatedAt
        )
    }

    func parseBoolValue(_ raw: String?) -> Bool? {
        let normalized = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "1", "true", "yes", "y":
            return true
        case "0", "false", "no", "n":
            return false
        default:
            return nil
        }
    }
}
