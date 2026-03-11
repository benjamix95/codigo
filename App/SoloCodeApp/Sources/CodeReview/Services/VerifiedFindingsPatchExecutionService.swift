import CoderEngine
import Foundation

@MainActor
enum VerifiedFindingsPatchExecutionService {
    static func execute(
        action: String,
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        workspaceRoot: String,
        preferredProviderId: String?,
        providerRegistry: ProviderRegistry
    ) async throws -> CodeReviewSessionSnapshot {
        let service = ReviewPatchWorkflowService()
        let runtime = ReviewPatchRustBridge.startRuntime(
            action: action,
            sessionId: snapshot.sessionId,
            findingId: findingId,
            conversationId: snapshot.conversationId,
            snapshot: snapshot
        )
        guard let runtime else {
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
                currentSnapshot = upsertingPatch(in: currentSnapshot, artifact: verified)
            case "apply_patch":
                guard let artifact = currentSnapshot.patches.first(where: { $0.findingId == findingId }) else {
                    throw ReviewPatchWorkflowError.invalidPatch
                }
                let applied = try await service.applyPatch(artifact: artifact, workspaceRoot: workspaceRoot)
                currentSnapshot = upsertingPatch(in: currentSnapshot, artifact: applied)
            case "revalidate_finding":
                guard let artifact = currentSnapshot.patches.first(where: { $0.findingId == findingId }) else {
                    throw ReviewPatchWorkflowError.invalidPatch
                }
                let revalidated = try await service.revalidatePatch(artifact: artifact, workspaceRoot: workspaceRoot)
                currentSnapshot = upsertingPatch(in: currentSnapshot, artifact: revalidated)
            case "rollback_patch":
                guard let artifact = currentSnapshot.patches.first(where: { $0.findingId == findingId }) else {
                    throw ReviewPatchWorkflowError.invalidPatch
                }
                let rolledBack = try await service.rollbackPatch(artifact: artifact, workspaceRoot: workspaceRoot)
                currentSnapshot = upsertingPatch(in: currentSnapshot, artifact: rolledBack)
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
                currentSnapshot = upsertingPatch(in: currentSnapshot, artifact: opened)
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
                currentSnapshot = upsertingPatch(in: currentSnapshot, artifact: merged)
            case "resolve_conflicts":
                guard let artifact = currentSnapshot.patches.first(where: { $0.findingId == findingId }) else {
                    throw ReviewPatchWorkflowError.invalidPatch
                }
                let resolved = try await service.resolveConflicts(
                    artifact: artifact,
                    preferredProviderId: preferredProviderId,
                    providerRegistry: providerRegistry
                )
                currentSnapshot = upsertingPatch(in: currentSnapshot, artifact: resolved)
            case "close_finding":
                currentSnapshot = try closeFinding(
                    snapshot: currentSnapshot,
                    findingId: findingId
                )
            default:
                break
            }
                let updated = ReviewPatchRustBridge.applyRuntimeResult(
                    runtimeId: runtimeId ?? "",
                    succeeded: true,
                    errorMessage: nil
                )
                runtimeId = updated?.runtimeId ?? runtimeId
                currentStep = updated?.currentStep
            } catch {
                let failed = ReviewPatchRustBridge.applyRuntimeResult(
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

    static func upsertingPatch(
        in snapshot: CodeReviewSessionSnapshot,
        artifact: ReviewPatchArtifact
    ) -> CodeReviewSessionSnapshot {
        var patches = snapshot.patches
        if let index = patches.firstIndex(where: { $0.id == artifact.id || $0.findingId == artifact.findingId }) {
            patches[index] = artifact
        } else {
            patches.append(artifact)
        }

        var findings = snapshot.findings
        if let index = findings.firstIndex(where: { $0.id == artifact.findingId }) {
            findings[index].patchArtifactId = artifact.id
            findings[index].status = switch artifact.status {
            case .draft: .patchPreparing
            case .verified: .patchReady
            case .applied: .patchApplied
            case .applyFailed: .patchFailed
            case .prOpened: .prOpened
            case .merged: .merged
            case .conflict, .rolledBack: .blocked
            }
        }

        return snapshot.copying(
            findings: findings,
            patches: patches,
            events: snapshot.events + [
                CodeReviewSessionEvent.patchPrepared(
                    patchId: artifact.id,
                    findingId: artifact.findingId
                ),
            ],
            outcome: snapshot.copying(findings: findings, patches: patches).buildOutcomeSummary()
        )
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
        return upsertingPatch(in: snapshot, artifact: verified)
    }

    private static func closeFinding(
        snapshot: CodeReviewSessionSnapshot,
        findingId: String
    ) throws -> CodeReviewSessionSnapshot {
        guard let findingIndex = snapshot.findings.firstIndex(where: { $0.id == findingId }) else {
            throw ReviewPatchWorkflowError.reviewNotVerified
        }
        let currentStatus = snapshot.findings[findingIndex].status
        let patch = snapshot.findings[findingIndex].patchArtifactId.flatMap { patchId in
            snapshot.patches.first(where: { $0.id == patchId })
        } ?? snapshot.patches.first(where: { $0.findingId == findingId })

        let canClose: Bool
        switch currentStatus {
        case .merged, .dismissed, .wontFix, .closed:
            canClose = true
        case .patchApplied, .fixApplied:
            canClose = patch?.validationStatus == .passed
        default:
            canClose = false
        }
        guard canClose else {
            throw ReviewPatchWorkflowError.applyFailed("Finding cannot be closed until the patch is validated or the finding is already resolved.")
        }

        var findings = snapshot.findings
        findings[findingIndex].status = .closed
        let updated = snapshot.copying(
            findings: findings,
            events: snapshot.events + [
                CodeReviewSessionEvent(
                    type: .outcomePublished,
                    detail: "Finding \(findingId) closed",
                    metadata: ["finding_id": findingId, "reason": "closed"]
                )
            ]
        )
        return updated.copying(
            mutationSequence: updated.mutationSequence,
            outcome: updated.buildOutcomeSummary(),
            lastUpdatedAt: Date()
        )
    }
}
