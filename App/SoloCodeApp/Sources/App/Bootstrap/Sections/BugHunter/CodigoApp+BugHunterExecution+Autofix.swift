import CoderEngine
import Foundation

extension CodigoApp {
    @MainActor
    func executeBugHunterAutofix(
        _ command: MCPSharedBugHunterCommand,
        mode: BugHunterAutofixExecutionMode
    ) async -> (success: Bool, message: String) {
        guard let snapshot = MCPSharedState.readBugHunterSnapshot(runId: command.runId),
              let reviewSessionId = snapshot.reviewSessionId else {
            return (false, "BugHunter run not found")
        }
        guard let reviewSnapshot = resolveCodeReviewSnapshot(sessionId: reviewSessionId, conversationId: nil) else {
            return (false, "Linked review session not found")
        }

        let autofixable = reviewSnapshot.findings
            .filter { ($0.confidence ?? 0) >= 0.9 && $0.verifiedAt != nil }
            .sorted { ($0.confidence ?? 0) > ($1.confidence ?? 0) }

        guard let finding = autofixable.first else {
            return (false, "No autofixable verified bug found")
        }
        let commandPayload = [
            "session_id": reviewSessionId,
            "finding_id": finding.id,
        ]

        let preparedResult = await runBugHunterPatchCommand(
            action: "prepare_patch",
            sessionId: reviewSessionId,
            payload: commandPayload,
            findingId: finding.id,
            expectedStatus: nil,
            expectedVerifyStatus: .verified,
            bugHunterRunId: command.runId
        )
        guard preparedResult.success else { return preparedResult }

        if mode == .commit {
            return await runCommittedBugHunterAutofix(
                command: command,
                snapshot: snapshot,
                reviewSessionId: reviewSessionId,
                finding: finding,
                payload: commandPayload
            )
        }

        if mode == .apply {
            let applyResult = await runBugHunterPatchCommand(
                action: "apply_patch",
                sessionId: reviewSessionId,
                payload: commandPayload,
                findingId: finding.id,
                expectedStatus: .applied,
                expectedVerifyStatus: .verified,
                bugHunterRunId: command.runId
            )
            guard applyResult.success else { return applyResult }
            return await runBugHunterPatchCommand(
                action: "revalidate_finding",
                sessionId: reviewSessionId,
                payload: commandPayload,
                findingId: finding.id,
                expectedStatus: nil,
                expectedVerifyStatus: .verified,
                bugHunterRunId: command.runId
            )
        }

        return preparedResult
    }

    @MainActor
    func runBugHunterPatchCommand(
        action: String,
        sessionId: String,
        payload: [String: String],
        findingId: String,
        expectedStatus: ReviewPatchStatus?,
        expectedVerifyStatus: ReviewPatchVerifyStatus,
        bugHunterRunId: String
    ) async -> (success: Bool, message: String) {
        let patchCommand = MCPSharedState.enqueueCodeReviewCommand(
            action: action,
            sessionId: sessionId,
            conversationId: nil,
            payload: payload
        )
        await processPendingCodeReviewCommandsOnce()
        MCPSharedState.refreshCodeReviewCommandHeartbeat(id: patchCommand.id)

        guard let latestReviewSnapshot = resolveCodeReviewSnapshot(sessionId: sessionId, conversationId: nil),
              let patch = latestReviewSnapshot.patches.first(where: { $0.findingId == findingId }) else {
            return (false, "Patch workflow did not produce an artifact for action \(action)")
        }
        guard patch.verifyStatus == expectedVerifyStatus else {
            return (false, "Patch workflow returned verify_status=\(patch.verifyStatus.rawValue) for action \(action)")
        }
        if let expectedStatus, patch.status != expectedStatus {
            return (false, "Patch workflow returned status=\(patch.status.rawValue) for action \(action)")
        }
        await refreshBugHunterSnapshotFromReview(runId: bugHunterRunId)

        let successMessage: String
        switch action {
        case "prepare_patch":
            successMessage = "Autofix preview prepared"
        case "apply_patch":
            successMessage = "Autofix applied"
        case "revalidate_finding":
            successMessage = "Autofix revalidation completed"
        case "rollback_patch":
            successMessage = "Autofix rollback completed"
        default:
            successMessage = "Autofix step \(action) completed"
        }
        return (true, successMessage)
    }

    @MainActor
    func cancelBugHunterRun(
        _ command: MCPSharedBugHunterCommand
    ) async -> (success: Bool, message: String) {
        guard let snapshot = MCPSharedState.readBugHunterSnapshot(runId: command.runId) else {
            return (false, "BugHunter run not found")
        }
        let cancelled = MCPSharedBugHunterSnapshot(
            runId: snapshot.runId,
            conversationId: snapshot.conversationId,
            reviewSessionId: snapshot.reviewSessionId,
            sourceKind: snapshot.sourceKind,
            triggerKind: snapshot.triggerKind,
            gitRoot: snapshot.gitRoot,
            branchName: snapshot.branchName,
            primaryCommit: snapshot.primaryCommit,
            relatedCommits: snapshot.relatedCommits,
            status: .cancelled,
            startedAt: snapshot.startedAt,
            completedAt: Date(),
            lastUpdatedAt: Date(),
            lastMessage: "BugHunter run cancelled",
            autoFixMode: snapshot.autoFixMode,
            cleanAfterFix: snapshot.cleanAfterFix,
            verifiedFindingsCount: snapshot.verifiedFindingsCount,
            candidateFindingsCount: snapshot.candidateFindingsCount,
            lastRevalidationVerdict: snapshot.lastRevalidationVerdict,
            securityGateReady: snapshot.securityGateReady
        )
        MCPSharedState.writeBugHunterSnapshot(cancelled)
        return (true, "BugHunter run \(command.runId) cancelled")
    }

    @MainActor
    func refreshBugHunterSnapshotFromReview(runId: String) async {
        guard let bugHunterSnapshot = MCPSharedState.readBugHunterSnapshot(runId: runId),
              let reviewSessionId = bugHunterSnapshot.reviewSessionId,
              let reviewSnapshot = resolveCodeReviewSnapshot(sessionId: reviewSessionId, conversationId: nil) else {
            return
        }
        let projection = reviewSnapshot.verifiedFindingsProjection
        let gate = reviewSnapshot.verifiedFindings.map(VerifiedFindingsSecurityGateService.evaluate)
        let lastVerdict = reviewSnapshot.verifiedFindings?.canonicalSnapshot.revalidationReports.values
            .sorted(by: { $0.createdAt > $1.createdAt })
            .first?.verdict.rawValue
        let updated = MCPSharedBugHunterSnapshot(
            runId: bugHunterSnapshot.runId,
            conversationId: bugHunterSnapshot.conversationId,
            reviewSessionId: bugHunterSnapshot.reviewSessionId,
            sourceKind: bugHunterSnapshot.sourceKind,
            triggerKind: bugHunterSnapshot.triggerKind,
            gitRoot: bugHunterSnapshot.gitRoot,
            branchName: bugHunterSnapshot.branchName,
            primaryCommit: bugHunterSnapshot.primaryCommit,
            relatedCommits: bugHunterSnapshot.relatedCommits,
            status: bugHunterSnapshot.status,
            startedAt: bugHunterSnapshot.startedAt,
            completedAt: bugHunterSnapshot.completedAt,
            lastUpdatedAt: Date(),
            lastMessage: bugHunterSnapshot.lastMessage,
            autoFixMode: bugHunterSnapshot.autoFixMode,
            cleanAfterFix: bugHunterSnapshot.cleanAfterFix,
            verifiedFindingsCount: projection.verifiedQueue.count,
            candidateFindingsCount: projection.candidateQueue.count,
            lastRevalidationVerdict: lastVerdict,
            securityGateReady: gate?.ready
        )
        MCPSharedState.writeBugHunterSnapshot(updated)
    }

    @MainActor
    private func runCommittedBugHunterAutofix(
        command: MCPSharedBugHunterCommand,
        snapshot: MCPSharedBugHunterSnapshot,
        reviewSessionId: String,
        finding: CodeReviewFinding,
        payload: [String: String]
    ) async -> (success: Bool, message: String) {
        let applyResult = await runBugHunterPatchCommand(
            action: "apply_patch",
            sessionId: reviewSessionId,
            payload: payload,
            findingId: finding.id,
            expectedStatus: .applied,
            expectedVerifyStatus: .verified,
            bugHunterRunId: command.runId
        )
        guard applyResult.success else { return applyResult }
        let revalidateResult = await runBugHunterPatchCommand(
            action: "revalidate_finding",
            sessionId: reviewSessionId,
            payload: payload,
            findingId: finding.id,
            expectedStatus: nil,
            expectedVerifyStatus: .verified,
            bugHunterRunId: command.runId
        )
        guard revalidateResult.success else {
            _ = await runBugHunterPatchCommand(
                action: "rollback_patch",
                sessionId: reviewSessionId,
                payload: payload,
                findingId: finding.id,
                expectedStatus: .rolledBack,
                expectedVerifyStatus: .verified,
                bugHunterRunId: command.runId
            )
            return revalidateResult
        }

        let gitRoot = workspaceStore.activeWorkspacePaths.first?.path ?? snapshot.gitRoot
        guard !gitRoot.isEmpty else { return (false, "Missing git root for autofix commit") }
        do {
            let commit = try await GitService().commit(
                gitRoot: gitRoot,
                message: "fix(bughunter): \(finding.filePath.components(separatedBy: "/").last ?? finding.filePath)",
                includeUnstaged: false
            )
            enqueueBugHunterPostCommit(commit: commit, gitRoot: gitRoot, triggerKind: .manual)
            let updated = MCPSharedBugHunterSnapshot(
                runId: snapshot.runId,
                conversationId: snapshot.conversationId,
                reviewSessionId: snapshot.reviewSessionId,
                sourceKind: .autofixRound,
                triggerKind: snapshot.triggerKind,
                gitRoot: snapshot.gitRoot,
                branchName: snapshot.branchName,
                primaryCommit: commit.sha,
                relatedCommits: snapshot.relatedCommits,
                status: .completed,
                startedAt: snapshot.startedAt,
                completedAt: Date(),
                lastUpdatedAt: Date(),
                lastMessage: "Autofix commit \(commit.shortSha) created",
                autoFixMode: snapshot.autoFixMode,
                cleanAfterFix: false,
                verifiedFindingsCount: snapshot.verifiedFindingsCount,
                candidateFindingsCount: snapshot.candidateFindingsCount,
                lastRevalidationVerdict: "fixed_verified",
                securityGateReady: snapshot.securityGateReady
            )
            MCPSharedState.writeBugHunterSnapshot(updated)
            return (true, "Autofix commit \(commit.shortSha) created")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
