import CoderEngine
import Foundation

extension ReviewPatchWorkflowService {
    func applyPatch(
        artifact: ReviewPatchArtifact,
        workspaceRoot: String
    ) async throws -> ReviewPatchArtifact {
        guard artifact.verifyStatus == .verified else {
            throw ReviewPatchWorkflowError.patchNotVerified
        }
        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)
        let patchFile = try writePatchTempFile(artifact.patchText, prefix: artifact.id)
        defer { try? FileManager.default.removeItem(at: patchFile) }

        do {
            _ = try gitService.runGit(["apply", "--3way", "--whitespace=nowarn", patchFile.path], gitRoot: gitRoot)
            let validation = try await runValidation(
                trigger: .reviewPatchApply,
                workspaceRoot: gitRoot,
                touchedFiles: artifact.touchedFiles,
                patchText: artifact.patchText,
                workspaceContainsPatch: true
            )
            guard validation.status == .passed else {
                _ = try? gitService.runGit(["apply", "-R", "--3way", patchFile.path], gitRoot: gitRoot)
                throw ReviewPatchWorkflowError.validationFailed(validation.summaryLine)
            }
            var applied = artifact
            applied.status = .applied
            applied.verifyStatus = .verified
            applied.validationRunId = validation.runId
            applied.validationStatus = validation.status
            applied.validationSummary = ValidationReportFormatter.summary(for: validation)
            applied.rollbackRef = "reverse:\(artifact.id)"
            applied.applyMessage = applied.validationSummary
            applied.updatedAt = Date()
            return applied
        } catch {
            _ = try? gitService.runGit(["apply", "-R", "--3way", patchFile.path], gitRoot: gitRoot)
            throw ReviewPatchWorkflowError.applyFailed(error.localizedDescription)
        }
    }

    func revalidatePatch(
        artifact: ReviewPatchArtifact,
        workspaceRoot: String
    ) async throws -> ReviewPatchArtifact {
        guard artifact.status == .applied else {
            throw ReviewPatchWorkflowError.applyFailed("La patch non risulta applicata nel workspace corrente.")
        }
        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)
        let validation = try await runValidation(
            trigger: .reviewPatchApply,
            workspaceRoot: gitRoot,
            touchedFiles: artifact.touchedFiles,
            patchText: nil,
            workspaceContainsPatch: true
        )
        var updated = artifact
        updated.validationRunId = validation.runId
        updated.validationStatus = validation.status
        updated.validationSummary = ValidationReportFormatter.summary(for: validation)
        updated.applyMessage = updated.validationSummary
        updated.status = validation.status == .passed ? .applied : .applyFailed
        updated.updatedAt = Date()
        return updated
    }

    func rollbackPatch(
        artifact: ReviewPatchArtifact,
        workspaceRoot: String
    ) async throws -> ReviewPatchArtifact {
        guard artifact.status == .applied else {
            throw ReviewPatchWorkflowError.rollbackUnavailable
        }
        guard artifact.rollbackRef != nil else {
            throw ReviewPatchWorkflowError.rollbackUnavailable
        }
        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)
        let patchFile = try writePatchTempFile(artifact.patchText, prefix: "\(artifact.id)-rollback")
        defer { try? FileManager.default.removeItem(at: patchFile) }

        do {
            _ = try gitService.runGit(["apply", "-R", "--3way", "--whitespace=nowarn", patchFile.path], gitRoot: gitRoot)
            var rolledBack = artifact
            rolledBack.status = .rolledBack
            rolledBack.applyMessage = "Rollback applied successfully"
            rolledBack.updatedAt = Date()
            return rolledBack
        } catch {
            throw ReviewPatchWorkflowError.applyFailed("Rollback fallito: \(error.localizedDescription)")
        }
    }
}

extension CodigoApp {
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
                    DispatchQueue.main.async { [taskActivityStore = self.taskActivityStore] in
                        taskActivityStore.scheduleCodeReviewSnapshotIngest(snapshot, conversationId: conversationId)
                    }
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
        let snapshot = taskActivityStore.codeReviewSnapshot(sessionId: sessionId, conversationId: conversationId)
            ?? MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId)
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
                await persistLiveReviewState(liveState, conversationId: conversationId)
            }
            return succeeded
        }

        let result = await persistReviewSnapshotMutation(sessionId: sessionId, conversationId: conversationId) { snapshot in
            var findings = snapshot.findings
            guard let index = findings.firstIndex(where: { $0.id == findingId }) else { return nil }
            findings[index].status = .fixApplied
            return snapshot.copying(
                findings: findings,
                events: snapshot.events + [.findingFixApplied(findingId: findingId)],
                outcome: snapshot.copying(findings: findings).buildOutcomeSummary()
            )
        }
        return result.success
    }
}
