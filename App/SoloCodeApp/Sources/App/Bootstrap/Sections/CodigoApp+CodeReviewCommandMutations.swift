import CoderEngine
import Foundation

extension CodigoApp {
    func verifiedCommandMeta(
        for command: MCPSharedCodeReviewCommand,
        entityId: String
    ) -> VerifiedCommandMeta {
        VerifiedCommandMeta(
            commandId: command.id,
            entityId: entityId,
            issuedBy: "mcp_review_command",
            issuedFrom: .mcp,
            requestFingerprint: "\(command.action)|\(entityId)|\(command.sessionId ?? "no-session")",
            expectedEntityVersion: nil
        )
    }

    nonisolated
    func synchronizedVerifiedFindingsSnapshot(
        _ snapshot: CodeReviewSessionSnapshot,
        conversationId: UUID?
    ) -> CodeReviewSessionSnapshot {
        let entryPoint: VerifiedFindingOriginEntryPoint = {
            if conversationId != nil {
                return .reviewChat
            }
            return .mcp
        }()
        let envelope = VerifiedFindingsSessionSyncService.sync(
            snapshot: snapshot,
            existingEnvelope: snapshot.verifiedFindings,
            entryPoint: entryPoint
        )
        return snapshot.copying(verifiedFindings: envelope)
    }

    @MainActor
    func persistLiveReviewState(
        _ state: CodeReviewSessionState,
        conversationId: UUID?
    ) async {
        let snapshot = synchronizedVerifiedFindingsSnapshot(
            await state.snapshot(),
            conversationId: conversationId
        )
        MCPSharedState.writeCodeReviewSnapshot(snapshot)
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
        let entityId = command.payload["finding_id"] ?? sessionId
        let meta = verifiedCommandMeta(for: command, entityId: entityId)
        if let liveState = await ReviewSessionRegistry.shared.state(sessionId: sessionId) {
            do {
                let outcome = try await VerifiedFindingsCommandCoordinator.shared.execute(
                    meta: meta,
                    successSummary: "\(command.action) \(entityId)"
                ) {
                    let succeeded = await apply(liveState, command.payload)
                    guard succeeded else {
                        throw ReviewPatchWorkflowError.applyFailed("Unable to update the requested finding")
                    }
                    await self.persistLiveReviewState(
                        liveState,
                        conversationId: command.conversationId.flatMap(UUID.init(uuidString:))
                    )
                }
                return (true, outcomeSummary(outcome))
            } catch {
                return (false, error.localizedDescription)
            }
        }

        do {
            let outcome = try await VerifiedFindingsCommandCoordinator.shared.execute(
                meta: meta,
                successSummary: "\(command.action) \(entityId)"
            ) {
                let result = await self.persistReviewSnapshotMutation(
                    sessionId: sessionId,
                    conversationId: command.conversationId.flatMap(UUID.init(uuidString:))
                ) { snapshot in
                    mutateReviewSnapshot(snapshot: snapshot, command: command)
                }
                if !result.success {
                    throw ReviewPatchWorkflowError.applyFailed(result.message)
                }
            }
            return (true, outcomeSummary(outcome))
        } catch {
            return (false, error.localizedDescription)
        }
    }

    @MainActor
    func persistReviewSnapshotMutation(
        sessionId: String,
        conversationId: UUID? = nil,
        mutate: (CodeReviewSessionSnapshot) -> CodeReviewSessionSnapshot?
    ) async -> (success: Bool, message: String) {
        guard let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId),
              (conversationId == nil || snapshot.conversationId == conversationId),
              let updated = mutate(snapshot) else {
            return (false, "Review session not found")
        }
        let synchronized = synchronizedVerifiedFindingsSnapshot(updated, conversationId: conversationId)
        MCPSharedState.writeCodeReviewSnapshot(synchronized)
        await ReviewSessionRegistry.shared.recordSnapshot(synchronized)
        taskActivityStore.ingestCodeReviewSnapshot(
            synchronized,
            conversationId: synchronized.conversationId
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
        case "close_finding":
            guard let findingId = command.payload["finding_id"],
                  let index = findings.firstIndex(where: { $0.id == findingId }) else {
                return nil
            }
            let patch = snapshot.patches.first(where: { $0.findingId == findingId })
            let currentStatus = findings[index].status
            let canClose: Bool
            switch currentStatus {
            case .merged, .dismissed, .wontFix, .closed:
                canClose = true
            case .patchApplied, .fixApplied:
                canClose = patch?.validationStatus == .passed
            default:
                canClose = false
            }
            guard canClose else { return nil }
            findings[index].status = .closed
            events.append(CodeReviewSessionEvent(
                type: .outcomePublished,
                detail: "Finding \(findingId) closed",
                metadata: ["finding_id": findingId, "reason": command.payload["reason"] ?? "closed"]
            ))
        default:
            return nil
        }

        return snapshot.copying(
            findings: findings,
            events: events,
            outcome: snapshot.copying(findings: findings).buildOutcomeSummary(),
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

    func outcomeSummary(_ outcome: VerifiedFindingsCommandOutcome) -> String {
        switch outcome {
        case .executed(let summary):
            return summary
        case .deduplicated(let summary):
            return "Deduplicated: \(summary)"
        }
    }
}
