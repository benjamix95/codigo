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

@MainActor
enum ReviewPatchRuntimeFinalizationService {
    typealias PrepareHandler = @MainActor (
        CodeReviewSessionSnapshot,
        [String],
        String,
        any LLMProvider
    ) async throws -> CodeReviewSessionSnapshot

    static var prepareHandler: PrepareHandler = defaultPrepareVerifiedPatches

    static func prepareVerifiedPatches(
        snapshot: CodeReviewSessionSnapshot,
        findingIds: [String],
        workspaceRoot: String,
        executionProvider: any LLMProvider
    ) async throws -> CodeReviewSessionSnapshot {
        try await prepareHandler(
            snapshot,
            findingIds,
            workspaceRoot,
            executionProvider
        )
    }

    static func resetForTests() {
        prepareHandler = defaultPrepareVerifiedPatches
    }

    private static func defaultPrepareVerifiedPatches(
        snapshot: CodeReviewSessionSnapshot,
        findingIds: [String],
        workspaceRoot: String,
        executionProvider: any LLMProvider
    ) async throws -> CodeReviewSessionSnapshot {
        let service = ReviewPatchWorkflowService()
        var current = snapshot

        for findingId in findingIds {
            guard let finding = current.findings.first(where: { $0.id == findingId }) else {
                continue
            }
            do {
                let prepared = try await service.preparePatch(
                    finding: finding,
                    snapshot: current,
                    executionProvider: executionProvider,
                    workspaceRoot: workspaceRoot
                )
                let verified = try await service.verifyPatch(
                    artifact: prepared,
                    workspaceRoot: workspaceRoot
                )
                current = VerifiedFindingsService.upsertingPatch(
                    in: current,
                    artifact: verified
                )
            } catch {
                let findings = current.findings.map { item -> CodeReviewFinding in
                    guard item.id == findingId else { return item }
                    var updated = item
                    updated.status = .patchFailed
                    updated.comments.append(
                        FindingComment(
                            author: "system",
                            content: "Patch preview non disponibile: \(error.localizedDescription)"
                        )
                    )
                    return updated
                }
                current = current.copying(
                    findings: findings,
                    outcome: current.copying(findings: findings).buildOutcomeSummary(
                        summaryOverride: "Patch preparation failed for \(findingId): \(error.localizedDescription)"
                    )
                )
            }
        }

        return current
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
                let stream = try await provider.send(prompt: prompt, context: context, imageURLs: nil)
                for try await _ in stream {}

                let snapshot = await sessionState.snapshot()
                let autoPrepared = await autoPrepareVerifiedPatchesIfRequested(command: command, sessionState: sessionState)
                var sourceStateUpdated = true
                if let onSuccess {
                    sourceStateUpdated = await onSuccess()
                }

                if snapshot.phase == .completed || snapshot.phase == .failed {
                    await persistLiveReviewState(sessionState, conversationId: sessionState.conversationId)
                }
                let finalize = ReviewCommandRustBridge.finalizeDeferred(
                    sessionId: snapshot.sessionId,
                    phase: snapshot.phase,
                    lastError: snapshot.lastError,
                    autoPrepareSucceeded: autoPrepared,
                    sourceStateSucceeded: sourceStateUpdated
                )
                let status: MCPSharedCodeReviewCommand.Status
                let message: String
                if let finalize {
                    status = finalize.commandStatus == "completed" ? .completed : .failed
                    message = finalize.resultMessage
                } else if snapshot.phase == .completed {
                    if !autoPrepared {
                        status = .failed
                        message = "Code review completed, but automatic patch preview preparation failed"
                    } else if !sourceStateUpdated {
                        status = .failed
                        message = "Code review completed, but the source finding state could not be updated"
                    } else {
                        status = .completed
                        message = "Code review session \(snapshot.sessionId) completed"
                    }
                } else {
                    status = .failed
                    message = snapshot.lastError ?? "Code review session \(snapshot.sessionId) did not complete successfully"
                }
                MCPSharedState.markCodeReviewCommand(id: command.id, status: status, resultMessage: message)
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
            await persistLiveReviewState(sessionState, conversationId: sessionState.conversationId)
        }
        return true
    }
}
