import CoderEngine
import Foundation

struct CodeReviewCommandOutcome {
    let success: Bool
    let message: String
    let deferred: Bool

    static func immediate(success: Bool, message: String) -> Self {
        Self(success: success, message: message, deferred: false)
    }

    static func deferred(message: String) -> Self {
        Self(success: true, message: message, deferred: true)
    }
}

extension CodigoApp {
    @MainActor
    func launchDeferredReviewCommand(
        command: MCPSharedCodeReviewCommand,
        provider: any LLMProvider,
        sessionState: CodeReviewSessionState,
        prompt: String,
        context: WorkspaceContext,
        onSuccess: (@MainActor () async -> Bool)? = nil
    ) {
        Task { @MainActor in
            let heartbeat = Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard !Task.isCancelled else { break }
                    MCPSharedState.refreshCodeReviewCommandHeartbeat(id: command.id)
                }
            }
            defer { heartbeat.cancel() }
            do {
                let stream = try await provider.send(
                    prompt: prompt,
                    context: context,
                    imageURLs: nil
                )
                for try await _ in stream {}

                let snapshot = await sessionState.snapshot()
                guard snapshot.phase == .completed else {
                    let failureMessage = snapshot.lastError
                        ?? "Code review session \(snapshot.sessionId) did not complete successfully"
                    MCPSharedState.markCodeReviewCommand(
                        id: command.id,
                        status: .failed,
                        resultMessage: failureMessage
                    )
                    return
                }

                let autoPrepared = await autoPrepareVerifiedPatchesIfRequested(
                    command: command,
                    sessionState: sessionState
                )
                guard autoPrepared else {
                    MCPSharedState.markCodeReviewCommand(
                        id: command.id,
                        status: .failed,
                        resultMessage: "Code review completed, but automatic patch preview preparation failed"
                    )
                    return
                }

                if let onSuccess {
                    let succeeded = await onSuccess()
                    guard succeeded else {
                        MCPSharedState.markCodeReviewCommand(
                            id: command.id,
                            status: .failed,
                            resultMessage: "Code review completed, but the source finding state could not be updated"
                        )
                        return
                    }
                }

                await persistLiveReviewState(
                    sessionState,
                    conversationId: sessionState.conversationId
                )
                MCPSharedState.markCodeReviewCommand(
                    id: command.id,
                    status: .completed,
                    resultMessage: "Code review session \(snapshot.sessionId) completed"
                )
            } catch {
                await sessionState.fail(error: error.localizedDescription)
                MCPSharedState.markCodeReviewCommand(
                    id: command.id,
                    status: .failed,
                    resultMessage: error.localizedDescription
                )
            }
        }
    }

    @MainActor
    func makeCommandReviewSessionState(
        sessionId: String,
        conversationId: UUID?,
        config: SessionConfig
    ) -> CodeReviewSessionState {
        CodeReviewSessionState(
            sessionId: sessionId,
            conversationId: conversationId,
            config: config,
            onStateChange: { snapshot in
                Task { @MainActor in
                    MCPSharedState.writeCodeReviewSnapshot(snapshot)
                    await ReviewSessionRegistry.shared.recordSnapshot(snapshot)
                    self.taskActivityStore.ingestCodeReviewSnapshot(
                        snapshot,
                        conversationId: conversationId
                    )
                }
            }
        )
    }

    @MainActor
    func codeReviewCommandContext() -> WorkspaceContext {
        CodeReviewCommandRuntimeHooks.workspaceContext(for: self)
    }

    @MainActor
    func resolveCodeReviewSnapshot(
        sessionId: String,
        conversationId: UUID?
    ) -> CodeReviewSessionSnapshot? {
        let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) ?? MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId)
        guard let snapshot else { return nil }
        guard conversationId == nil || snapshot.conversationId == conversationId else {
            return nil
        }
        return snapshot
    }

    @MainActor
    func makeTargetedFixSessionId(sourceSessionId: String) -> String {
        let suffix = String(UUID().uuidString.lowercased().prefix(8))
        let candidate = "\(sourceSessionId)-fix-\(suffix)"
        if let sanitized = MCPSharedState.sanitizedCodeReviewSessionId(candidate) {
            return sanitized
        }
        return UUID().uuidString.lowercased()
    }

    @MainActor
    func markFindingFixApplied(
        sessionId: String,
        conversationId: UUID?,
        findingId: String
    ) async -> Bool {
        if let liveState = await ReviewSessionRegistry.shared.state(sessionId: sessionId) {
            let succeeded = await liveState.applyFix(findingId: findingId)
            if succeeded {
                await persistLiveReviewState(
                    liveState,
                    conversationId: conversationId
                )
            }
            return succeeded
        }

        let result = await persistReviewSnapshotMutation(
            sessionId: sessionId,
            conversationId: conversationId
        ) { snapshot in
            var findings = snapshot.findings
            guard let index = findings.firstIndex(where: { $0.id == findingId }) else {
                return nil
            }
            findings[index].status = .fixApplied
            return snapshot.copying(
                findings: findings,
                events: snapshot.events + [
                    .findingFixApplied(findingId: findingId)
                ],
                outcome: snapshot.copying(findings: findings).buildOutcomeSummary()
            )
        }
        return result.success
    }

    @MainActor
    private func autoPrepareVerifiedPatchesIfRequested(
        command: MCPSharedCodeReviewCommand,
        sessionState: CodeReviewSessionState
    ) async -> Bool {
        guard parseBoolValue(command.payload["auto_prepare_verified_patches"]) == true else {
            return true
        }
        guard let workspaceRoot = workspaceStore.activeWorkspacePaths.first?.path else {
            return false
        }

        let snapshot = await sessionState.snapshot()
        let eligibleFindingIds = Set(
            autoPrepareEligibleFindingIds(
                snapshot: snapshot,
                originFilter: command.payload["auto_prepare_origin_filter"]
            )
        )
        let findingsToPrepare = snapshot.findings.filter { eligibleFindingIds.contains($0.id) }

        guard !findingsToPrepare.isEmpty else { return true }

        for finding in findingsToPrepare {
            do {
                let updated = try await VerifiedFindingsPatchExecutionService.execute(
                    action: "prepare_patch",
                    snapshot: await sessionState.snapshot(),
                    findingId: finding.id,
                    workspaceRoot: workspaceRoot,
                    preferredProviderId: providerRegistry.selectedProviderId,
                    providerRegistry: providerRegistry
                )
                guard let artifact = updated.patches.first(where: { $0.findingId == finding.id }) else {
                    return false
                }
                await sessionState.upsertPatch(artifact)
            } catch {
                _ = await sessionState.addComment(
                    findingId: finding.id,
                    comment: FindingComment(
                        author: "system",
                        content: "Patch preview non disponibile: \(error.localizedDescription)"
                    )
                )
            }
            await persistLiveReviewState(
                sessionState,
                conversationId: sessionState.conversationId
            )
        }

        return true
    }

    func autoPrepareEligibleFindingIds(
        snapshot: CodeReviewSessionSnapshot,
        originFilter: String?
    ) -> [String] {
        let allowedOrigins = Set(
            (originFilter ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        return snapshot.findings.compactMap { finding in
            guard finding.patchArtifactId == nil else { return nil }
            guard finding.verifiedAt != nil || finding.verificationReport != nil else { return nil }
            if !allowedOrigins.isEmpty && !allowedOrigins.contains(finding.origin.rawValue) {
                return nil
            }
            return finding.id
        }
    }
}
