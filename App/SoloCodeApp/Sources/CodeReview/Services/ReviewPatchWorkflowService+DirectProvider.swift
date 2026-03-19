import CoderEngine
import Foundation

extension ReviewPatchWorkflowService {
    func prepareDraftArtifact(
        finding: CodeReviewFinding,
        patchText: String,
        touchedFiles: [String],
        baseBranchName: String
    ) throws -> ReviewPatchArtifact {
        let response: ReviewPatchPrepareResultBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_prepare_result",
            request: ReviewPatchPrepareResultBridgeRequest(
                schemaVersion: 1,
                findingId: finding.id,
                patchText: patchText,
                touchedFiles: touchedFiles,
                baseBranchName: baseBranchName,
                verificationReport: finding.verificationReport
            )
        )
        guard let response else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch prepare result runtime required but unavailable"
            )
        }
        if response.isError {
            throw ReviewPatchWorkflowError.applyFailed(
                response.message ?? "Unable to derive patch prepare result"
            )
        }
        guard let diffPreview = response.diffPreview,
              let riskScore = response.riskScore,
              let statusRaw = response.status,
              let status = ReviewPatchStatus(rawValue: statusRaw),
              let verifyStatusRaw = response.verifyStatus,
              let verifyStatus = ReviewPatchVerifyStatus(rawValue: verifyStatusRaw),
              let prStatusRaw = response.prStatus,
              let prStatus = ReviewPatchPRStatus(rawValue: prStatusRaw),
              let mergeStatusRaw = response.mergeStatus,
              let mergeStatus = ReviewPatchMergeStatus(rawValue: mergeStatusRaw),
              let resolvedBaseBranchName = response.baseBranchName else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch prepare result response was incomplete"
            )
        }

        return ReviewPatchArtifact(
            findingId: finding.id,
            patchText: patchText,
            diffPreview: diffPreview,
            touchedFiles: touchedFiles,
            riskScore: riskScore,
            status: status,
            verifyStatus: verifyStatus,
            prStatus: prStatus,
            mergeStatus: mergeStatus,
            baseBranchName: resolvedBaseBranchName,
            verificationReport: response.verificationReport
        )
    }

    func preparePatchContext(
        finding: CodeReviewFinding,
        snapshot: CodeReviewSessionSnapshot
    ) throws -> ReviewPatchPrepareContext {
        let request = ReviewPatchPrepareContextRequest(
            schemaVersion: 1,
            sessionId: snapshot.sessionId,
            findingId: finding.id,
            filePath: finding.filePath,
            lineNumber: finding.lineNumber,
            message: finding.message,
            verificationReport: finding.verificationReport,
            suggestedFix: finding.suggestedFix,
            expectedInvariant: finding.expectedInvariant,
            reproOrReasoning: finding.reproOrReasoning
        )
        let response: ReviewPatchPrepareContextResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_prepare_context",
            request: request
        )
        guard let response else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch prepare context runtime required but unavailable"
            )
        }
        if response.isError {
            throw ReviewPatchWorkflowError.applyFailed(
                response.message ?? "Unable to derive patch prepare context"
            )
        }
        guard let branchName = response.branchName,
              let prompt = response.prompt else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch prepare context response was incomplete"
            )
        }
        return ReviewPatchPrepareContext(branchName: branchName, prompt: prompt)
    }

    func preparePatch(
        finding: CodeReviewFinding,
        snapshot: CodeReviewSessionSnapshot,
        executionProvider: any LLMProvider,
        workspaceRoot: String
    ) async throws -> ReviewPatchArtifact {
        guard finding.verifiedAt != nil || finding.verificationReport != nil else {
            throw ReviewPatchWorkflowError.reviewNotVerified
        }
        let prepareContext = try preparePatchContext(
            finding: finding,
            snapshot: snapshot
        )

        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)
        let baseBranch = try gitService.currentBranch(gitRoot: gitRoot)
        let branchName = prepareContext.branchName
        let worktreePath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codigo-review-patches")
            .appendingPathComponent(branchName.replacingOccurrences(of: "/", with: "-"))
            .path

        try? gitService.removeWorktree(gitRoot: gitRoot, worktreePath: worktreePath, force: true)
        try? gitService.deleteBranch(name: branchName, gitRoot: gitRoot, force: true)
        try gitService.createWorktree(
            gitRoot: gitRoot,
            branchName: branchName,
            fromBranch: baseBranch,
            worktreePath: worktreePath
        )
        defer {
            try? gitService.removeWorktree(gitRoot: gitRoot, worktreePath: worktreePath, force: true)
            try? gitService.deleteBranch(name: branchName, gitRoot: gitRoot, force: true)
        }

        _ = try await mergeAIService.runHeadlessPrompt(
            provider: executionProvider,
            gitRoot: worktreePath,
            prompt: prepareContext.prompt
        )

        let patchText = try gitService.runGit(["diff", "--no-ext-diff"], gitRoot: worktreePath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !patchText.isEmpty else {
            throw ReviewPatchWorkflowError.emptyDiff
        }

        let touchedFiles = try gitService.runGit(["diff", "--name-only"], gitRoot: worktreePath)
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        let artifact = try prepareDraftArtifact(
            finding: finding,
            patchText: patchText,
            touchedFiles: touchedFiles,
            baseBranchName: baseBranch
        )
        return try await validatePreparedArtifact(
            artifact,
            workspaceRoot: worktreePath,
            trigger: .reviewPatchPreview,
            workspaceContainsPatch: true
        )
    }
}

struct ReviewPatchPrepareContext {
    let branchName: String
    let prompt: String
}

private struct ReviewPatchPrepareContextRequest: Encodable {
    let schemaVersion: Int
    let sessionId: String
    let findingId: String
    let filePath: String
    let lineNumber: Int?
    let message: String
    let verificationReport: String?
    let suggestedFix: String?
    let expectedInvariant: String?
    let reproOrReasoning: String?
}

private struct ReviewPatchPrepareContextResponse: Decodable {
    let isError: Bool
    let message: String?
    let branchName: String?
    let prompt: String?
}

private struct ReviewPatchPrepareResultBridgeRequest: Encodable {
    let schemaVersion: Int
    let findingId: String
    let patchText: String
    let touchedFiles: [String]
    let baseBranchName: String
    let verificationReport: String?
}

private struct ReviewPatchPrepareResultBridgeResponse: Decodable {
    let isError: Bool
    let message: String?
    let diffPreview: String?
    let riskScore: Double?
    let status: String?
    let verifyStatus: String?
    let prStatus: String?
    let mergeStatus: String?
    let baseBranchName: String?
    let verificationReport: String?
}

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
        guard let snapshot = resolveCodeReviewSnapshot(sessionId: sessionId, conversationId: conversationId) else {
            return .immediate(success: false, message: "Review session not found")
        }
        guard let workspaceRoot = workspaceStore.activeWorkspacePaths.first?.path else {
            return .immediate(success: false, message: "No active workspace is available for code review")
        }

        do {
            let synchronizedSnapshot = synchronizedVerifiedFindingsSnapshot(snapshot, conversationId: snapshot.conversationId)
            let meta = verifiedCommandMeta(for: command, entityId: findingId, snapshot: synchronizedSnapshot)
            let outcome = try await VerifiedFindingsCommandCoordinator.shared.execute(
                meta: meta,
                successSummary: "\(command.action) \(findingId)",
                currentEntityVersion: { [self] in
                    await currentVerifiedEntityVersion(
                        sessionId: sessionId,
                        conversationId: conversationId,
                        entityId: findingId
                    )
                }
            ) {
                let updated = try await self.executePatchWorkflowCommand(
                    command: command,
                    snapshot: snapshot,
                    findingId: findingId,
                    workspaceRoot: workspaceRoot
                )
                let synchronized = self.synchronizedVerifiedFindingsSnapshot(updated, conversationId: updated.conversationId)
                MCPSharedState.writeCodeReviewSnapshot(synchronized)
                await ReviewSessionRegistry.shared.recordSnapshot(synchronized)
                await MainActor.run {
                    taskActivityStore.scheduleCodeReviewSnapshotIngest(
                        synchronized,
                        conversationId: synchronized.conversationId
                    )
                }
            }
            switch outcome {
            case .executed(let summary), .deduplicated(let summary):
                return .immediate(success: true, message: summary)
            }
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
        switch command.action {
        case "verify_finding":
            return try verifyFinding(snapshot: snapshot, findingId: findingId, workspaceRoot: workspaceRoot)
        default:
            return try await VerifiedFindingsPatchExecutionService.execute(
                action: command.action,
                snapshot: snapshot,
                findingId: findingId,
                workspaceRoot: workspaceRoot,
                preferredProviderId: providerRegistry.selectedProviderId,
                providerRegistry: providerRegistry
            )
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
}
