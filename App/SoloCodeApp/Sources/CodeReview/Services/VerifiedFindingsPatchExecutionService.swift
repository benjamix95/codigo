import CoderEngine
import Foundation

@MainActor
enum VerifiedFindingsPatchExecutionService {
    typealias ExecuteHandler = @MainActor (String, CodeReviewSessionSnapshot, String, String, String?, ProviderRegistry) async throws -> CodeReviewSessionSnapshot

    static var executeHandler: ExecuteHandler = defaultExecute

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

    static func resetForTests() {
        executeHandler = defaultExecute
    }
    private static func defaultExecute(
        action: String,
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        workspaceRoot: String,
        preferredProviderId: String?,
        providerRegistry: ProviderRegistry
    ) async throws -> CodeReviewSessionSnapshot {
        let service = ReviewPatchWorkflowService()
        let runtime = startPatchRuntime(
            action: action,
            sessionId: snapshot.sessionId,
            findingId: findingId,
            conversationId: snapshot.conversationId,
            snapshot: snapshot
        )
        guard let runtime else {
            if action == "close_finding" {
                return try VerifiedFindingsService.closeFinding(
                    snapshot: snapshot,
                    findingId: findingId
                )
            }
            throw ReviewPatchWorkflowError.invalidPatch
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
                switch step {
            case "prepare_patch":
                currentSnapshot = try await preparePatch(
                    snapshot: currentSnapshot,
                    findingId: findingId,
                    workspaceRoot: workspaceRoot,
                    preferredProviderId: preferredProviderId,
                    providerRegistry: providerRegistry,
                    service: service
                )
            case "verify_patch":
                guard let artifact = currentSnapshot.patches.first(where: { $0.findingId == findingId }) else {
                    throw ReviewPatchWorkflowError.invalidPatch
                }
                let verified = try await service.verifyPatch(artifact: artifact, workspaceRoot: workspaceRoot)
                currentSnapshot = VerifiedFindingsService.upsertingPatch(in: currentSnapshot, artifact: verified)
            case "apply_patch":
                guard let artifact = currentSnapshot.patches.first(where: { $0.findingId == findingId }) else {
                    throw ReviewPatchWorkflowError.invalidPatch
                }
                let applied = try await service.applyPatch(artifact: artifact, workspaceRoot: workspaceRoot)
                currentSnapshot = VerifiedFindingsService.upsertingPatch(in: currentSnapshot, artifact: applied)
            case "revalidate_finding":
                guard let artifact = currentSnapshot.patches.first(where: { $0.findingId == findingId }) else {
                    throw ReviewPatchWorkflowError.invalidPatch
                }
                let revalidated = try await service.revalidatePatch(artifact: artifact, workspaceRoot: workspaceRoot)
                currentSnapshot = VerifiedFindingsService.upsertingPatch(in: currentSnapshot, artifact: revalidated)
            case "rollback_patch":
                guard let artifact = currentSnapshot.patches.first(where: { $0.findingId == findingId }) else {
                    throw ReviewPatchWorkflowError.invalidPatch
                }
                let rolledBack = try await service.rollbackPatch(artifact: artifact, workspaceRoot: workspaceRoot)
                currentSnapshot = VerifiedFindingsService.upsertingPatch(in: currentSnapshot, artifact: rolledBack)
            case "open_pr":
                guard let artifact = currentSnapshot.patches.first(where: { $0.findingId == findingId }),
                      let finding = currentSnapshot.findings.first(where: { $0.id == findingId }) else {
                    throw ReviewPatchWorkflowError.invalidPatch
                }
                let title = "fix(review): \(finding.filePath.components(separatedBy: "/").last ?? finding.filePath)"
                let body = "\(finding.message)\n\n\(finding.verificationReport ?? "Verification unavailable")"
                let opened = try service.openPullRequest(
                    artifact: artifact,
                    title: title,
                    body: body,
                    workspaceRoot: workspaceRoot
                )
                currentSnapshot = VerifiedFindingsService.upsertingPatch(in: currentSnapshot, artifact: opened)
            case "merge_pr":
                guard let artifact = currentSnapshot.patches.first(where: { $0.findingId == findingId }) else {
                    throw ReviewPatchWorkflowError.invalidPatch
                }
                let merged = try await service.mergePullRequest(
                    artifact: artifact,
                    preferredProviderId: preferredProviderId,
                    providerRegistry: providerRegistry,
                    workspaceRoot: workspaceRoot,
                    safeOnly: true
                )
                currentSnapshot = VerifiedFindingsService.upsertingPatch(in: currentSnapshot, artifact: merged)
            case "resolve_conflicts":
                guard let artifact = currentSnapshot.patches.first(where: { $0.findingId == findingId }) else {
                    throw ReviewPatchWorkflowError.invalidPatch
                }
                let resolved = try await service.resolveConflicts(
                    artifact: artifact,
                    preferredProviderId: preferredProviderId,
                    providerRegistry: providerRegistry
                )
                currentSnapshot = VerifiedFindingsService.upsertingPatch(in: currentSnapshot, artifact: resolved)
            case "close_finding":
                currentSnapshot = try VerifiedFindingsService.closeFinding(
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
                runtimeId = updated?.runtimeId ?? runtimeId
                currentStep = updated?.currentStep
            } catch {
                let failed = applyPatchRuntimeResult(
                    runtimeId: runtimeId ?? "",
                    succeeded: false,
                    errorMessage: error.localizedDescription
                )
                throw ReviewPatchWorkflowError.applyFailed(
                    failed?.errorMessage ?? error.localizedDescription
                )
            }
        }
        return currentSnapshot
    }

    private static func preparePatch(
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        workspaceRoot: String,
        preferredProviderId: String?,
        providerRegistry: ProviderRegistry,
        service: ReviewPatchWorkflowService
    ) async throws -> CodeReviewSessionSnapshot {
        guard let finding = snapshot.findings.first(where: { $0.id == findingId }) else {
            throw ReviewPatchWorkflowError.reviewNotVerified
        }
        let prepared = try await service.preparePatch(
            finding: finding,
            snapshot: snapshot,
            preferredProviderId: preferredProviderId,
            providerRegistry: providerRegistry,
            workspaceRoot: workspaceRoot
        )
        let verified = try await service.verifyPatch(artifact: prepared, workspaceRoot: workspaceRoot)
        return VerifiedFindingsService.upsertingPatch(in: snapshot, artifact: verified)
    }

    private static func startPatchRuntime(
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
    private static func applyPatchRuntimeResult(
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
}
