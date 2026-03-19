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
            return try applyPatchResult(
                artifact: artifact,
                validation: validation
            )
        } catch {
            _ = try? gitService.runGit(["apply", "-R", "--3way", patchFile.path], gitRoot: gitRoot)
            throw ReviewPatchWorkflowError.applyFailed(error.localizedDescription)
        }
    }

    func applyPatchResult(
        artifact: ReviewPatchArtifact,
        validation: ValidationRunResult
    ) throws -> ReviewPatchArtifact {
        let summary = ValidationReportFormatter.summary(for: validation)
        let response: ReviewPatchApplyResultBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_apply_result",
            request: ReviewPatchApplyResultBridgeRequest(
                schemaVersion: 1,
                patchId: artifact.id,
                findingId: artifact.findingId,
                success: true,
                validationRunId: validation.runId,
                validationStatus: validation.status.rawValue,
                validationSummary: summary,
                errorMessage: nil
            )
        )
        guard let response else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch apply result runtime required but unavailable"
            )
        }
        if response.isError {
            throw ReviewPatchWorkflowError.applyFailed(
                response.message ?? "Unable to derive patch apply result"
            )
        }
        guard let statusRaw = response.status,
              let status = ReviewPatchStatus(rawValue: statusRaw),
              let verifyStatusRaw = response.verifyStatus,
              let verifyStatus = ReviewPatchVerifyStatus(rawValue: verifyStatusRaw),
              let rollbackRef = response.rollbackRef,
              let validationStatusRaw = response.validationStatus,
              let validationStatus = ValidationStatus(rawValue: validationStatusRaw) else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch apply result response was incomplete"
            )
        }

        var updated = artifact
        updated.status = status
        updated.verifyStatus = verifyStatus
        updated.validationRunId = response.validationRunId
        updated.validationStatus = validationStatus
        updated.validationSummary = response.validationSummary
        updated.rollbackRef = rollbackRef
        updated.applyMessage = response.applyMessage
        updated.updatedAt = Date()
        return updated
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

private struct ReviewPatchApplyResultBridgeRequest: Encodable {
    let schemaVersion: Int
    let patchId: String
    let findingId: String
    let success: Bool
    let validationRunId: String?
    let validationStatus: String?
    let validationSummary: String?
    let errorMessage: String?
}

private struct ReviewPatchApplyResultBridgeResponse: Decodable {
    let isError: Bool
    let message: String?
    let status: String?
    let verifyStatus: String?
    let rollbackRef: String?
    let validationRunId: String?
    let validationStatus: String?
    let validationSummary: String?
    let applyMessage: String?
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
