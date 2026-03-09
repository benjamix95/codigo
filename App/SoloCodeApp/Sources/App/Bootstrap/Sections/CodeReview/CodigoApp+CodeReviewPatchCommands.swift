import CoderEngine
import Foundation

extension CodigoApp {
    @MainActor
    func handlePatchWorkflowCommand(
        _ command: MCPSharedCodeReviewCommand
    ) async -> CodeReviewCommandOutcome {
        guard let sessionId = command.sessionId,
              let findingId = command.payload["finding_id"] else {
            return .immediate(success: false, message: "Missing session_id or finding_id")
        }
        let conversationId = command.conversationId.flatMap(UUID.init(uuidString:))
        guard let snapshot = resolveCodeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else {
            return .immediate(success: false, message: "Review session not found")
        }
        guard let workspaceRoot = workspaceStore.activeWorkspacePaths.first?.path else {
            return .immediate(success: false, message: "No active workspace is available for code review")
        }

        do {
            let updated = try await executePatchWorkflowCommand(
                command: command,
                snapshot: snapshot,
                findingId: findingId,
                workspaceRoot: workspaceRoot
            )
            MCPSharedState.writeCodeReviewSnapshot(updated)
            await ReviewSessionRegistry.shared.recordSnapshot(updated)
            taskActivityStore.ingestCodeReviewSnapshot(updated, conversationId: updated.conversationId)
            return .immediate(success: true, message: "Review workflow command '\(command.action)' completed")
        } catch {
            return .immediate(success: false, message: error.localizedDescription)
        }
    }

    @MainActor
    private func executePatchWorkflowCommand(
        command: MCPSharedCodeReviewCommand,
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        workspaceRoot: String
    ) async throws -> CodeReviewSessionSnapshot {
        let service = ReviewPatchWorkflowService()
        switch command.action {
        case "verify_finding":
            return try verifyFinding(snapshot: snapshot, findingId: findingId, workspaceRoot: workspaceRoot)
        case "prepare_patch":
            return try await preparePatch(snapshot: snapshot, findingId: findingId, workspaceRoot: workspaceRoot, service: service)
        case "verify_patch":
            guard let artifact = snapshot.patches.first(where: { $0.findingId == findingId }) else {
                throw ReviewPatchWorkflowError.invalidPatch
            }
            let verified = try await service.verifyPatch(artifact: artifact, workspaceRoot: workspaceRoot)
            return upsertingPatch(in: snapshot, artifact: verified)
        case "apply_patch", "apply_fix":
            let preparedSnapshot = snapshot.patches.contains(where: { $0.findingId == findingId })
                ? snapshot
                : try await preparePatch(snapshot: snapshot, findingId: findingId, workspaceRoot: workspaceRoot, service: service)
            guard let artifact = preparedSnapshot.patches.first(where: { $0.findingId == findingId }) else {
                throw ReviewPatchWorkflowError.invalidPatch
            }
            let verifiedArtifact = try await service.verifyPatch(artifact: artifact, workspaceRoot: workspaceRoot)
            let verifiedSnapshot = upsertingPatch(in: preparedSnapshot, artifact: verifiedArtifact)
            let applied = try await service.applyPatch(artifact: verifiedArtifact, workspaceRoot: workspaceRoot)
            return upsertingPatch(in: verifiedSnapshot, artifact: applied)
        case "open_pr":
            guard let artifact = snapshot.patches.first(where: { $0.findingId == findingId }),
                  let finding = snapshot.findings.first(where: { $0.id == findingId }) else {
                throw ReviewPatchWorkflowError.invalidPatch
            }
            let title = "fix(review): \(finding.filePath.components(separatedBy: "/").last ?? finding.filePath)"
            let body = "\(finding.message)\n\n\(finding.verificationReport ?? "Verification unavailable")"
            let opened = try service.openPullRequest(artifact: artifact, title: title, body: body, workspaceRoot: workspaceRoot)
            return upsertingPatch(in: snapshot, artifact: opened)
        case "merge_pr":
            guard let artifact = snapshot.patches.first(where: { $0.findingId == findingId }) else {
                throw ReviewPatchWorkflowError.invalidPatch
            }
            let merged = try await service.mergePullRequest(
                artifact: artifact,
                preferredProviderId: providerRegistry.selectedProviderId,
                providerRegistry: providerRegistry,
                workspaceRoot: workspaceRoot,
                safeOnly: true
            )
            return upsertingPatch(in: snapshot, artifact: merged)
        case "resolve_conflicts":
            guard let artifact = snapshot.patches.first(where: { $0.findingId == findingId }) else {
                throw ReviewPatchWorkflowError.invalidPatch
            }
            let resolved = try await service.resolveConflicts(
                artifact: artifact,
                preferredProviderId: providerRegistry.selectedProviderId,
                providerRegistry: providerRegistry
            )
            return upsertingPatch(in: snapshot, artifact: resolved)
        default:
            return snapshot
        }
    }

    private func verifyFinding(
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        workspaceRoot: String
    ) throws -> CodeReviewSessionSnapshot {
        let workspaceURL = URL(fileURLWithPath: workspaceRoot)
        let scopeFiles = Set((snapshot.scope?.files ?? []).map {
            $0.hasPrefix("./") ? String($0.dropFirst(2)) : $0
        })

        var candidates = snapshot.candidates
        if let index = candidates.firstIndex(where: { $0.id == findingId }) {
            let result = ReviewCandidateVerificationService.verify(
                candidate: candidates[index],
                workspacePath: workspaceURL,
                scopeFiles: scopeFiles
            )
            candidates[index].verificationStatus = result.status
            candidates[index].verificationMethod = result.method
            candidates[index].verificationReport = result.report
            candidates[index].falsePositiveReason = result.falsePositiveReason
            candidates[index].verifiedAt = result.status == .verified ? Date() : nil
            var findings = snapshot.findings
            if result.status == .verified && !findings.contains(where: { $0.id == findingId }) {
                findings.append(.fromCandidate(candidates[index]))
            }
            return snapshot.copying(
                findings: findings,
                candidates: candidates,
                events: snapshot.events + [
                    result.status == .verified
                        ? .candidateVerified(candidateId: findingId)
                        : .candidateRejected(candidateId: findingId, reason: result.falsePositiveReason ?? result.status.rawValue),
                ],
                outcome: snapshot.copying(findings: findings, candidates: candidates).buildOutcomeSummary()
            )
        }
        return snapshot
    }

    private func preparePatch(
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        workspaceRoot: String,
        service: ReviewPatchWorkflowService
    ) async throws -> CodeReviewSessionSnapshot {
        guard let finding = snapshot.findings.first(where: { $0.id == findingId }) else {
            throw ReviewPatchWorkflowError.reviewNotVerified
        }
        let prepared = try await service.preparePatch(
            finding: finding,
            snapshot: snapshot,
            preferredProviderId: providerRegistry.selectedProviderId,
            providerRegistry: providerRegistry,
            workspaceRoot: workspaceRoot
        )
        let verified = try await service.verifyPatch(artifact: prepared, workspaceRoot: workspaceRoot)
        return upsertingPatch(in: snapshot, artifact: verified)
    }

    private func upsertingPatch(
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
            events: snapshot.events + [CodeReviewSessionEvent.patchPrepared(patchId: artifact.id, findingId: artifact.findingId)],
            outcome: snapshot.copying(findings: findings, patches: patches).buildOutcomeSummary()
        )
    }
}
