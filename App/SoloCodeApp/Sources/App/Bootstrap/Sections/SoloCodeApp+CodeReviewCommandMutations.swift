import CoderEngine
import Foundation

extension SoloCodeApp {
    func verifiedCommandMeta(
        for command: MCPSharedCodeReviewCommand,
        entityId: String,
        snapshot: CodeReviewSessionSnapshot? = nil
    ) -> VerifiedCommandMeta {
        let expectedEntityVersion = snapshot?
            .verifiedFindings?
            .canonicalSnapshot
            .findings[entityId]?
            .version
        return VerifiedCommandMeta(
            commandId: command.id,
            entityId: entityId,
            issuedBy: "mcp_review_command",
            issuedFrom: .mcp,
            requestFingerprint: "\(command.action)|\(entityId)|\(command.sessionId ?? "no-session")",
            expectedEntityVersion: expectedEntityVersion
        )
    }

    @MainActor
    func currentVerifiedEntityVersion(
        sessionId: String,
        conversationId: UUID?,
        entityId: String
    ) async -> Int? {
        if let liveState = await ReviewSessionRegistry.shared.state(sessionId: sessionId) {
            let snapshot = synchronizedVerifiedFindingsSnapshot(
                await liveState.snapshot(),
                conversationId: conversationId
            )
            return snapshot.verifiedFindings?.canonicalSnapshot.findings[entityId]?.version
        }
        guard let snapshot = resolveCodeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else {
            return nil
        }
        let synchronized = synchronizedVerifiedFindingsSnapshot(
            snapshot,
            conversationId: conversationId
        )
        return synchronized.verifiedFindings?.canonicalSnapshot.findings[entityId]?.version
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
        DispatchQueue.main.async { [taskActivityStore] in
            taskActivityStore.scheduleCodeReviewSnapshotIngest(
                snapshot,
                conversationId: conversationId ?? snapshot.conversationId
            )
        }
    }

    @MainActor
    func applyReviewMutation(
        _ command: MCPSharedCodeReviewCommand
    ) async -> (success: Bool, message: String) {
        guard let sessionId = command.sessionId else {
            return (false, "Missing session_id")
        }
        let entityId = command.payload["finding_id"] ?? sessionId
        let commandConversationId = command.conversationId.flatMap(UUID.init(uuidString:))
        if let liveState = await ReviewSessionRegistry.shared.state(sessionId: sessionId) {
            let liveSnapshot = synchronizedVerifiedFindingsSnapshot(
                await liveState.snapshot(),
                conversationId: commandConversationId
            )
            let meta = verifiedCommandMeta(
                for: command,
                entityId: entityId,
                snapshot: liveSnapshot
            )
            do {
                let outcome = try await VerifiedFindingsCommandCoordinator.shared.execute(
                    meta: meta,
                    successSummary: "\(command.action) \(entityId)",
                    currentEntityVersion: { [self] in
                        await currentVerifiedEntityVersion(
                            sessionId: sessionId,
                            conversationId: commandConversationId,
                            entityId: entityId
                        )
                    }
                ) {
                    let liveSnapshot = await liveState.snapshot()
                    guard let mutation = ReviewCommandRustBridge.mutateSnapshot(
                        liveSnapshot,
                        command: command
                    ),
                          !mutation.isError,
                          let findings = mutation.findings,
                          let events = mutation.events else {
                        throw ReviewPatchWorkflowError.applyFailed(
                            "Rust review command mutation unavailable"
                        )
                    }
                    let updatedConfig = mutation.config ?? liveSnapshot.config
                    let updated = liveSnapshot.copying(
                        findings: findings,
                        events: events,
                        config: updatedConfig,
                        outcome: liveSnapshot.copying(
                            findings: findings,
                            events: events,
                            config: updatedConfig
                        ).buildOutcomeSummary(),
                        lastUpdatedAt: Date()
                    )
                    await liveState.replaceCanonicalSnapshot(updated)
                    await self.persistLiveReviewState(
                        liveState,
                        conversationId: commandConversationId
                    )
                }
                return (true, outcomeSummary(outcome))
            } catch {
                return (false, error.localizedDescription)
            }
        }

        let baseSnapshot = resolveCodeReviewSnapshot(
            sessionId: sessionId,
            conversationId: commandConversationId
        )
        let synchronizedSnapshot = baseSnapshot.map {
            synchronizedVerifiedFindingsSnapshot($0, conversationId: commandConversationId)
        }
        let meta = verifiedCommandMeta(
            for: command,
            entityId: entityId,
            snapshot: synchronizedSnapshot
        )
        do {
            let outcome = try await VerifiedFindingsCommandCoordinator.shared.execute(
                meta: meta,
                successSummary: "\(command.action) \(entityId)",
                currentEntityVersion: { [self] in
                    await currentVerifiedEntityVersion(
                        sessionId: sessionId,
                        conversationId: commandConversationId,
                        entityId: entityId
                    )
                }
            ) {
                let result = await self.persistReviewSnapshotMutation(
                    sessionId: sessionId,
                    conversationId: commandConversationId
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
        DispatchQueue.main.async { [taskActivityStore] in
            taskActivityStore.scheduleCodeReviewSnapshotIngest(
                synchronized,
                conversationId: synchronized.conversationId
            )
        }
        return (true, "Snapshot updated")
    }

    nonisolated
    func mutateReviewSnapshot(
        snapshot: CodeReviewSessionSnapshot,
        command: MCPSharedCodeReviewCommand
    ) -> CodeReviewSessionSnapshot? {
        guard let mutation = ReviewCommandRustBridge.mutateSnapshot(
            snapshot,
            command: command
        ),
              !mutation.isError,
              let findings = mutation.findings,
              let events = mutation.events else {
            return nil
        }

        let updatedConfig = mutation.config ?? snapshot.config
        let updated = snapshot.copying(
            findings: findings,
            events: events,
            config: updatedConfig
        )
        return updated.copying(
            mutationSequence: updated.mutationSequence,
            outcome: updated.buildOutcomeSummary(),
            lastUpdatedAt: Date()
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
