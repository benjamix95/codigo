import CoderEngine
import Foundation

@MainActor
enum VerifiedFindingsPatchExecutionService {
    typealias ExecuteHandler = @MainActor (String, CodeReviewSessionSnapshot, String, String, String?, ProviderRegistry) async throws -> CodeReviewSessionSnapshot
    typealias ExecuteWithProviderHandler = @MainActor (String, CodeReviewSessionSnapshot, String, String, any LLMProvider) async throws -> CodeReviewSessionSnapshot
    typealias StartRuntimeHandler = @MainActor (String, String, String, UUID?, CodeReviewSessionSnapshot) -> ReviewPatchRuntimeResponse?
    typealias ApplyRuntimeResultHandler = @MainActor (String, Bool, String?) -> ReviewPatchRuntimeResponse?

    static var executeHandler: ExecuteHandler = defaultExecute
    static var executeWithProviderHandler: ExecuteWithProviderHandler = defaultExecuteWithProvider
    static var startRuntimeHandler: StartRuntimeHandler = defaultStartPatchRuntime
    static var applyRuntimeResultHandler: ApplyRuntimeResultHandler = defaultApplyPatchRuntimeResult

    static func execute(
        action: String,
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        workspaceRoot: String,
        preferredProviderId: String?,
        providerRegistry: ProviderRegistry
    ) async throws -> CodeReviewSessionSnapshot {
        try await executeHandler(
            action,
            snapshot,
            findingId,
            workspaceRoot,
            preferredProviderId,
            providerRegistry
        )
    }

    static func execute(
        action: String,
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        workspaceRoot: String,
        executionProvider: any LLMProvider
    ) async throws -> CodeReviewSessionSnapshot {
        try await executeWithProviderHandler(
            action,
            snapshot,
            findingId,
            workspaceRoot,
            executionProvider
        )
    }

    static func resetForTests() {
        executeHandler = defaultExecute
        executeWithProviderHandler = defaultExecuteWithProvider
        startRuntimeHandler = defaultStartPatchRuntime
        applyRuntimeResultHandler = defaultApplyPatchRuntimeResult
    }

    private static func defaultExecute(
        action: String,
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        workspaceRoot: String,
        preferredProviderId: String?,
        providerRegistry: ProviderRegistry
    ) async throws -> CodeReviewSessionSnapshot {
        return try await executeWithRuntime(
            action: action,
            snapshot: snapshot,
            findingId: findingId,
            workspaceRoot: workspaceRoot,
            executionProvider: nil,
            preferredProviderId: preferredProviderId,
            providerRegistry: providerRegistry
        )
    }

    private static func defaultExecuteWithProvider(
        action: String,
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        workspaceRoot: String,
        executionProvider: any LLMProvider
    ) async throws -> CodeReviewSessionSnapshot {
        try await executeWithRuntime(
            action: action,
            snapshot: snapshot,
            findingId: findingId,
            workspaceRoot: workspaceRoot,
            executionProvider: executionProvider,
            preferredProviderId: nil,
            providerRegistry: nil
        )
    }

    private static func executeWithRuntime(
        action: String,
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        workspaceRoot: String,
        executionProvider: (any LLMProvider)?,
        preferredProviderId: String?,
        providerRegistry: ProviderRegistry?
    ) async throws -> CodeReviewSessionSnapshot {
        let service = ReviewPatchWorkflowService()
        var resolvedExecutionProvider = executionProvider
        let runtime = startPatchRuntime(
            action: action,
            sessionId: snapshot.sessionId,
            findingId: findingId,
            conversationId: snapshot.conversationId,
            snapshot: snapshot
        )
        guard let runtime else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch runtime required but unavailable"
            )
        }
        if runtime.isError {
            throw ReviewPatchWorkflowError.applyFailed(
                runtime.errorMessage ?? "Unable to start patch runtime"
            )
        }

        var currentSnapshot = snapshot
        var runtimeId = runtime.runtimeId
        var currentStep = runtime.currentStep
        while let step = currentStep {
            do {
                let stepContext = try runtimeStepContext(
                    step: step,
                    snapshot: currentSnapshot,
                    findingId: findingId,
                    providerRegistryAvailable: providerRegistry != nil
                )
                switch step {
                case "prepare_patch":
                    if resolvedExecutionProvider == nil {
                        guard let providerRegistry else {
                            throw ReviewPatchWorkflowError.providerUnavailable
                        }
                        resolvedExecutionProvider = try service.mergeAIService.resolveProvider(
                            preferredProviderId: preferredProviderId,
                            providerRegistry: providerRegistry
                        )
                    }
                    currentSnapshot = try await preparePatch(
                        snapshot: currentSnapshot,
                        findingId: findingId,
                        workspaceRoot: workspaceRoot,
                        executionProvider: resolvedExecutionProvider!,
                        service: service
                    )
                case "verify_patch":
                    guard let artifact = stepContext.patch else { throw ReviewPatchWorkflowError.invalidPatch }
                    let verified = try await service.verifyPatch(artifact: artifact, workspaceRoot: workspaceRoot)
                    currentSnapshot = try upsertPatchWithRustMutation(
                        snapshot: currentSnapshot,
                        artifact: verified
                    )
                case "apply_patch":
                    guard let artifact = stepContext.patch else { throw ReviewPatchWorkflowError.invalidPatch }
                    let applied = try await service.applyPatch(artifact: artifact, workspaceRoot: workspaceRoot)
                    currentSnapshot = try upsertPatchWithRustMutation(
                        snapshot: currentSnapshot,
                        artifact: applied
                    )
                case "revalidate_finding":
                    guard let artifact = stepContext.patch else { throw ReviewPatchWorkflowError.invalidPatch }
                    let revalidated = try await service.revalidatePatch(artifact: artifact, workspaceRoot: workspaceRoot)
                    currentSnapshot = try upsertPatchWithRustMutation(
                        snapshot: currentSnapshot,
                        artifact: revalidated
                    )
                case "rollback_patch":
                    guard let artifact = stepContext.patch else { throw ReviewPatchWorkflowError.invalidPatch }
                    let rolledBack = try await service.rollbackPatch(artifact: artifact, workspaceRoot: workspaceRoot)
                    currentSnapshot = try upsertPatchWithRustMutation(
                        snapshot: currentSnapshot,
                        artifact: rolledBack
                    )
                case "open_pr":
                    guard let artifact = stepContext.patch,
                          let finding = stepContext.finding else { throw ReviewPatchWorkflowError.invalidPatch }
                    let openPRContext = try openPullRequestContext(finding: finding)
                    let opened = try service.openPullRequest(
                        artifact: artifact,
                        title: openPRContext.title,
                        body: openPRContext.body,
                        workspaceRoot: workspaceRoot
                    )
                    currentSnapshot = try upsertPatchWithRustMutation(
                        snapshot: currentSnapshot,
                        artifact: opened
                    )
                case "merge_pr":
                    guard let providerRegistry else { throw ReviewPatchWorkflowError.providerUnavailable }
                    guard let artifact = stepContext.patch else { throw ReviewPatchWorkflowError.invalidPatch }
                    let merged = try await service.mergePullRequest(
                        artifact: artifact,
                        preferredProviderId: preferredProviderId,
                        providerRegistry: providerRegistry,
                        workspaceRoot: workspaceRoot,
                        safeOnly: true
                    )
                    currentSnapshot = try upsertPatchWithRustMutation(
                        snapshot: currentSnapshot,
                        artifact: merged
                    )
                case "resolve_conflicts":
                    guard let providerRegistry else { throw ReviewPatchWorkflowError.providerUnavailable }
                    guard let artifact = stepContext.patch else { throw ReviewPatchWorkflowError.invalidPatch }
                    let resolved = try await service.resolveConflicts(
                        artifact: artifact,
                        preferredProviderId: preferredProviderId,
                        providerRegistry: providerRegistry
                    )
                    currentSnapshot = try upsertPatchWithRustMutation(
                        snapshot: currentSnapshot,
                        artifact: resolved
                    )
                case "close_finding":
                    currentSnapshot = try closeFindingWithRustMutation(
                        snapshot: currentSnapshot,
                        findingId: findingId
                    )
                default:
                    break
                }

                let updated = applyPatchRuntimeResult(
                    runtimeId: runtimeId ?? "",
                    succeeded: true,
                    errorMessage: nil
                )
                guard let updated else {
                    throw ReviewPatchWorkflowError.applyFailed(
                        "Rust patch runtime result bridge unavailable"
                    )
                }
                if updated.isError {
                    throw ReviewPatchWorkflowError.applyFailed(
                        updated.errorMessage ?? "Unable to advance patch runtime"
                    )
                }
                if updated.status == "failed" {
                    throw ReviewPatchWorkflowError.applyFailed(
                        updated.errorMessage ?? "Patch runtime failed"
                    )
                }
                runtimeId = updated.runtimeId ?? runtimeId
                currentStep = updated.status == "completed" ? nil : updated.currentStep
            } catch {
                let failed = applyPatchRuntimeResult(
                    runtimeId: runtimeId ?? "",
                    succeeded: false,
                    errorMessage: error.localizedDescription
                )
                guard let failed else {
                    throw ReviewPatchWorkflowError.applyFailed(
                        "Rust patch runtime result bridge unavailable"
                    )
                }
                if failed.isError {
                    throw ReviewPatchWorkflowError.applyFailed(
                        failed.errorMessage ?? "Unable to advance patch runtime"
                    )
                }
                throw ReviewPatchWorkflowError.applyFailed(
                    failed.errorMessage ?? error.localizedDescription
                )
            }
        }
        return currentSnapshot
    }
}
