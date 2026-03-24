import CoderEngine
import Foundation

@MainActor
extension VerifiedFindingsPatchExecutionService {
    static func preparePatch(
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        workspaceRoot: String,
        executionProvider: any LLMProvider,
        service: ReviewPatchWorkflowService
    ) async throws -> CodeReviewSessionSnapshot {
        guard let finding = snapshot.findings.first(where: { $0.id == findingId }) else {
            throw ReviewPatchWorkflowError.reviewNotVerified
        }
        let prepared = try await service.preparePatch(
            finding: finding,
            snapshot: snapshot,
            executionProvider: executionProvider,
            workspaceRoot: workspaceRoot
        )
        let verified = try await service.verifyPatch(artifact: prepared, workspaceRoot: workspaceRoot)
        return try upsertPatchWithRustMutation(
            snapshot: snapshot,
            artifact: verified
        )
    }

    static func closeFindingWithRustMutation(
        snapshot: CodeReviewSessionSnapshot,
        findingId: String
    ) throws -> CodeReviewSessionSnapshot {
        guard let mutation = ReviewCommandRustBridge.mutateSnapshot(
            snapshot,
            action: "close_finding",
            payload: ["finding_id": findingId]
        ),
              !mutation.isError else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch close finding mutator required but unavailable"
            )
        }
        guard let canonical = mutation.snapshot else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch close finding mutator response was incomplete"
            )
        }
        return canonical
    }

    static func upsertPatchWithRustMutation(
        snapshot: CodeReviewSessionSnapshot,
        artifact: ReviewPatchArtifact
    ) throws -> CodeReviewSessionSnapshot {
        guard let mutation = ReviewCommandRustBridge.upsertPatchSnapshot(
            snapshot,
            artifact: artifact
        ),
              !mutation.isError else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch snapshot upsert mutator required but unavailable"
            )
        }
        guard let canonical = mutation.snapshot else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch snapshot upsert mutator response was incomplete"
            )
        }
        return canonical
    }

    static func startPatchRuntime(
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        snapshot: CodeReviewSessionSnapshot
    ) -> ReviewPatchRuntimeResponse? {
        startRuntimeHandler(action, sessionId, findingId, conversationId, snapshot)
    }

    static func defaultStartPatchRuntime(
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        snapshot: CodeReviewSessionSnapshot
    ) -> ReviewPatchRuntimeResponse? {
        ReviewCoreBridge.call(
            functionName: "review_core_patch_start_runtime",
            request: ReviewPatchRuntimeStartRequest(
                schemaVersion: 1,
                action: action,
                sessionId: sessionId,
                findingId: findingId,
                conversationId: conversationId?.uuidString.lowercased(),
                snapshot: ReviewPatchRustSnapshot(snapshot: snapshot)
            )
        )
    }

    static func applyPatchRuntimeResult(
        runtimeId: String,
        succeeded: Bool,
        errorMessage: String?
    ) -> ReviewPatchRuntimeResponse? {
        applyRuntimeResultHandler(runtimeId, succeeded, errorMessage)
    }

    static func defaultApplyPatchRuntimeResult(
        runtimeId: String,
        succeeded: Bool,
        errorMessage: String?
    ) -> ReviewPatchRuntimeResponse? {
        ReviewCoreBridge.call(
            functionName: "review_core_patch_apply_runtime_result",
            request: ReviewPatchRuntimeResultRequest(
                schemaVersion: 1,
                runtimeId: runtimeId,
                succeeded: succeeded,
                errorMessage: errorMessage
            )
        )
    }

    static func runtimeStepContext(
        step: String,
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        providerRegistryAvailable: Bool
    ) throws -> ReviewPatchRuntimeStepContext {
        let response: ReviewPatchRuntimeStepContextResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_step_context",
            request: ReviewPatchRuntimeStepContextRequest(
                schemaVersion: 1,
                step: step,
                findingId: findingId,
                snapshot: ReviewPatchRustSnapshot(snapshot: snapshot),
                providerRegistryAvailable: providerRegistryAvailable
            )
        )
        guard let response else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch step context runtime required but unavailable"
            )
        }
        if response.isError {
            let message = response.message ?? "Unable to derive patch step context"
            if message == ReviewPatchWorkflowError.providerUnavailable.errorDescription {
                throw ReviewPatchWorkflowError.providerUnavailable
            }
            if message == ReviewPatchWorkflowError.reviewNotVerified.errorDescription {
                throw ReviewPatchWorkflowError.reviewNotVerified
            }
            if message == ReviewPatchWorkflowError.invalidPatch.errorDescription {
                throw ReviewPatchWorkflowError.invalidPatch
            }
            throw ReviewPatchWorkflowError.applyFailed(message)
        }
        return ReviewPatchRuntimeStepContext(
            patch: response.patch,
            finding: response.finding,
            providerRegistryRequired: response.providerRegistryRequired
        )
    }
}

struct ReviewPatchRuntimeStepContext {
    let patch: ReviewPatchArtifact?
    let finding: CodeReviewFinding?
    let providerRegistryRequired: Bool
}

struct ReviewPatchRuntimeStepContextRequest: Encodable {
    let schemaVersion: Int
    let step: String
    let findingId: String
    let snapshot: ReviewPatchRustSnapshot
    let providerRegistryAvailable: Bool
}

struct ReviewPatchRuntimeStepContextResponse: Decodable {
    let isError: Bool
    let message: String?
    let patch: ReviewPatchArtifact?
    let finding: CodeReviewFinding?
    let providerRegistryRequired: Bool
}
