import CoderEngine
import Foundation

extension ReviewPatchWorkflowService {
    func applyPatchExecutionContext(
        artifact: ReviewPatchArtifact
    ) throws -> ReviewPatchApplyExecutionContext {
        let response: ReviewPatchApplyExecutionContextResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_apply_execution_context",
            request: ReviewPatchApplyExecutionContextRequest(
                schemaVersion: 1,
                patchId: artifact.id,
                verifyStatus: artifact.verifyStatus.rawValue
            )
        )
        guard let response else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch apply execution context runtime required but unavailable"
            )
        }
        if response.isError {
            if response.message == ReviewPatchWorkflowError.patchNotVerified.errorDescription {
                throw ReviewPatchWorkflowError.patchNotVerified
            }
            throw ReviewPatchWorkflowError.applyFailed(
                response.message ?? "Unable to derive patch apply execution context"
            )
        }
        guard let patchFilePrefix = response.patchFilePrefix,
              let validationTrigger = response.validationTrigger,
              let workspaceContainsPatch = response.workspaceContainsPatch else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch apply execution context response was incomplete"
            )
        }
        return ReviewPatchApplyExecutionContext(
            patchFilePrefix: patchFilePrefix,
            validationTrigger: validationTrigger,
            workspaceContainsPatch: workspaceContainsPatch
        )
    }

    func revalidatePatchExecutionContext(
        artifact: ReviewPatchArtifact
    ) throws -> ReviewPatchRevalidateExecutionContext {
        let response: ReviewPatchRevalidateExecutionContextResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_revalidate_execution_context",
            request: ReviewPatchRevalidateExecutionContextRequest(
                schemaVersion: 1,
                status: artifact.status.rawValue
            )
        )
        guard let response else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch revalidate execution context runtime required but unavailable"
            )
        }
        if response.isError {
            throw ReviewPatchWorkflowError.applyFailed(
                response.message ?? "Unable to derive patch revalidate execution context"
            )
        }
        guard let validationTrigger = response.validationTrigger,
              let workspaceContainsPatch = response.workspaceContainsPatch else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch revalidate execution context response was incomplete"
            )
        }
        return ReviewPatchRevalidateExecutionContext(
            validationTrigger: validationTrigger,
            workspaceContainsPatch: workspaceContainsPatch
        )
    }

    func rollbackPatchExecutionContext(
        artifact: ReviewPatchArtifact
    ) throws -> ReviewPatchRollbackExecutionContext {
        let response: ReviewPatchRollbackExecutionContextResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_rollback_execution_context",
            request: ReviewPatchRollbackExecutionContextRequest(
                schemaVersion: 1,
                patchId: artifact.id,
                status: artifact.status.rawValue,
                rollbackRef: artifact.rollbackRef
            )
        )
        guard let response else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch rollback execution context runtime required but unavailable"
            )
        }
        if response.isError {
            throw ReviewPatchWorkflowError.applyFailed(
                response.message ?? "Unable to derive patch rollback execution context"
            )
        }
        guard let patchFilePrefix = response.patchFilePrefix else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch rollback execution context response was incomplete"
            )
        }
        return ReviewPatchRollbackExecutionContext(patchFilePrefix: patchFilePrefix)
    }

    func applyPatch(
        artifact: ReviewPatchArtifact,
        workspaceRoot: String
    ) async throws -> ReviewPatchArtifact {
        let context = try applyPatchExecutionContext(artifact: artifact)
        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)
        let patchFile = try writePatchTempFile(artifact.patchText, prefix: context.patchFilePrefix)
        defer { try? FileManager.default.removeItem(at: patchFile) }

        do {
            _ = try gitService.runGit(["apply", "--3way", "--whitespace=nowarn", patchFile.path], gitRoot: gitRoot)
            let validation = try await runValidation(
                trigger: .reviewPatchApply,
                workspaceRoot: gitRoot,
                touchedFiles: artifact.touchedFiles,
                patchText: artifact.patchText,
                workspaceContainsPatch: context.workspaceContainsPatch
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
        let context = try revalidatePatchExecutionContext(artifact: artifact)
        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)
        let validation = try await runValidation(
            trigger: .reviewPatchApply,
            workspaceRoot: gitRoot,
            touchedFiles: artifact.touchedFiles,
            patchText: nil,
            workspaceContainsPatch: context.workspaceContainsPatch
        )
        return try revalidatePatchResult(
            artifact: artifact,
            validation: validation
        )
    }

    func revalidatePatchResult(
        artifact: ReviewPatchArtifact,
        validation: ValidationRunResult
    ) throws -> ReviewPatchArtifact {
        let summary = ValidationReportFormatter.summary(for: validation)
        let response: ReviewPatchRevalidateResultBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_revalidate_result",
            request: ReviewPatchRevalidateResultBridgeRequest(
                schemaVersion: 1,
                patchId: artifact.id,
                validationRunId: validation.runId,
                validationStatus: validation.status.rawValue,
                validationSummary: summary
            )
        )
        guard let response else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch revalidate result runtime required but unavailable"
            )
        }
        if response.isError {
            throw ReviewPatchWorkflowError.applyFailed(
                response.message ?? "Unable to derive patch revalidate result"
            )
        }
        guard let statusRaw = response.status,
              let status = ReviewPatchStatus(rawValue: statusRaw),
              let validationStatusRaw = response.validationStatus,
              let validationStatus = ValidationStatus(rawValue: validationStatusRaw) else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch revalidate result response was incomplete"
            )
        }
        var updated = artifact
        updated.validationRunId = response.validationRunId
        updated.validationStatus = validationStatus
        updated.validationSummary = response.validationSummary
        updated.applyMessage = response.applyMessage
        updated.status = status
        updated.updatedAt = Date()
        return updated
    }

    func rollbackPatch(
        artifact: ReviewPatchArtifact,
        workspaceRoot: String
    ) async throws -> ReviewPatchArtifact {
        let context = try rollbackPatchExecutionContext(artifact: artifact)
        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)
        let patchFile = try writePatchTempFile(artifact.patchText, prefix: context.patchFilePrefix)
        defer { try? FileManager.default.removeItem(at: patchFile) }

        do {
            _ = try gitService.runGit(["apply", "-R", "--3way", "--whitespace=nowarn", patchFile.path], gitRoot: gitRoot)
            return try rollbackPatchResult(artifact: artifact)
        } catch {
            throw ReviewPatchWorkflowError.applyFailed("Rollback fallito: \(error.localizedDescription)")
        }
    }

    func rollbackPatchResult(
        artifact: ReviewPatchArtifact
    ) throws -> ReviewPatchArtifact {
        let response: ReviewPatchRollbackResultBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_rollback_result",
            request: ReviewPatchRollbackResultBridgeRequest(
                schemaVersion: 1,
                patchId: artifact.id,
                success: true,
                errorMessage: nil
            )
        )
        guard let response else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch rollback result runtime required but unavailable"
            )
        }
        if response.isError {
            throw ReviewPatchWorkflowError.applyFailed(
                response.message ?? "Unable to derive patch rollback result"
            )
        }
        guard let statusRaw = response.status,
              let status = ReviewPatchStatus(rawValue: statusRaw) else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch rollback result response was incomplete"
            )
        }
        var updated = artifact
        updated.status = status
        updated.applyMessage = response.applyMessage
        updated.updatedAt = Date()
        return updated
    }
}

struct ReviewPatchApplyExecutionContext {
    let patchFilePrefix: String
    let validationTrigger: String
    let workspaceContainsPatch: Bool
}

struct ReviewPatchRevalidateExecutionContext {
    let validationTrigger: String
    let workspaceContainsPatch: Bool
}

struct ReviewPatchRollbackExecutionContext {
    let patchFilePrefix: String
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

private struct ReviewPatchApplyExecutionContextRequest: Encodable {
    let schemaVersion: Int
    let patchId: String
    let verifyStatus: String
}

private struct ReviewPatchApplyExecutionContextResponse: Decodable {
    let isError: Bool
    let message: String?
    let patchFilePrefix: String?
    let validationTrigger: String?
    let workspaceContainsPatch: Bool?
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

private struct ReviewPatchRevalidateResultBridgeRequest: Encodable {
    let schemaVersion: Int
    let patchId: String
    let validationRunId: String?
    let validationStatus: String?
    let validationSummary: String?
}

private struct ReviewPatchRevalidateExecutionContextRequest: Encodable {
    let schemaVersion: Int
    let status: String
}

private struct ReviewPatchRevalidateExecutionContextResponse: Decodable {
    let isError: Bool
    let message: String?
    let validationTrigger: String?
    let workspaceContainsPatch: Bool?
}

private struct ReviewPatchRevalidateResultBridgeResponse: Decodable {
    let isError: Bool
    let message: String?
    let status: String?
    let validationRunId: String?
    let validationStatus: String?
    let validationSummary: String?
    let applyMessage: String?
}

private struct ReviewPatchRollbackResultBridgeRequest: Encodable {
    let schemaVersion: Int
    let patchId: String
    let success: Bool
    let errorMessage: String?
}

private struct ReviewPatchRollbackExecutionContextRequest: Encodable {
    let schemaVersion: Int
    let patchId: String
    let status: String
    let rollbackRef: String?
}

private struct ReviewPatchRollbackExecutionContextResponse: Decodable {
    let isError: Bool
    let message: String?
    let patchFilePrefix: String?
}

private struct ReviewPatchRollbackResultBridgeResponse: Decodable {
    let isError: Bool
    let message: String?
    let status: String?
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
