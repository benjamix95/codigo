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
        var current = snapshot

        for findingId in findingIds {
            guard current.findings.contains(where: { $0.id == findingId }) else {
                continue
            }
            do {
                current = try await VerifiedFindingsPatchExecutionService.execute(
                    action: "prepare_patch",
                    snapshot: current,
                    findingId: findingId,
                    workspaceRoot: workspaceRoot,
                    executionProvider: executionProvider
                )
            } catch {
                guard let reduced = reducePatchPrepareFailure(
                    snapshot: current,
                    findingId: findingId,
                    message: error.localizedDescription
                ) else {
                    throw ReviewPatchWorkflowError.applyFailed(
                        "Rust review session reducer required but unavailable"
                    )
                }
                current = reduced
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
                } else {
                    status = .failed
                    message = "Rust deferred review finalization runtime required but unavailable"
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
        let response: ReviewPatchAutoPrepareTargetsResponse? = ReviewCoreBridge.call(
            functionName: "review_core_select_auto_prepare_targets",
            request: ReviewPatchAutoPrepareTargetsRequest(
                schemaVersion: 1,
                snapshot: snapshot,
                originFilter: originFilter
            )
        )
        guard response?.error == nil else { return [] }
        return response?.panelState ?? []
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
                guard let reduced = reducePatchPrepareFailure(
                    snapshot: await sessionState.snapshot(),
                    findingId: finding.id,
                    message: error.localizedDescription
                ) else {
                    return false
                }
                await sessionState.replaceCanonicalSnapshot(reduced)
            }
            await persistLiveReviewState(sessionState, conversationId: sessionState.conversationId)
        }
        return true
    }
}

private func reducePatchPrepareFailure(
    snapshot: CodeReviewSessionSnapshot,
    findingId: String,
    message: String
) -> CodeReviewSessionSnapshot? {
    let response: ReviewPatchPrepareFailureReductionResponse? = ReviewCoreBridge.call(
        functionName: "review_core_session_apply_action",
        request: ReviewPatchPrepareFailureReductionRequest(
            schemaVersion: 1,
            operation: "mark_patch_prepare_failed",
            snapshot: snapshot,
            findingId: findingId,
            error: message
        )
    )
    guard response?.error == nil else { return nil }
    return response?.snapshot
}

private struct ReviewPatchAutoPrepareTargetsRequest: Encodable {
    let schemaVersion: Int
    let snapshot: CodeReviewSessionSnapshot
    let originFilter: String?
}

private struct ReviewPatchAutoPrepareTargetsResponse: Decodable {
    let error: ReviewPatchAutoPrepareTargetsError?
    let panelState: [String]?
}

private struct ReviewPatchAutoPrepareTargetsError: Decodable {
    let code: String
    let message: String
}

private struct ReviewPatchPrepareFailureReductionRequest: Encodable {
    let schemaVersion: Int
    let operation: String
    let snapshot: CodeReviewSessionSnapshot
    let findingId: String
    let error: String
}

private struct ReviewPatchPrepareFailureReductionResponse: Decodable {
    let error: ReviewPatchPrepareFailureReductionError?
    let snapshot: CodeReviewSessionSnapshot?
}

private struct ReviewPatchPrepareFailureReductionError: Decodable {
    let code: String
    let message: String
}
