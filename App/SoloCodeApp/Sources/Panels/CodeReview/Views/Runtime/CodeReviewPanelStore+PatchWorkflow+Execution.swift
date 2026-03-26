import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func preparePatch(sessionId: String, findingId: String) async {
        guard workspaceStore.activeWorkspacePaths.first?.path != nil else {
            await markPatchFailure(
                sessionId: sessionId,
                findingId: findingId,
                message: ReviewPatchWorkflowError.missingWorkspace.localizedDescription
            )
            return
        }
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ),
              let finding = snapshot.findings.first(where: { $0.id == findingId }),
        let workspaceRoot = workspaceStore.activeWorkspacePaths.first?.path else {
            return
        }

        guard finding.isBugConfirmedForPatchPreparation else {
            appendVerifiedFindingSystemMessage(
                sessionId: sessionId,
                findingId: findingId,
                title: "Verifica richiesta",
                detail:
                    "Esegui «Verifica bug approfondita» e attendi un esito confermato prima di preparare la patch."
            )
            return
        }

        do {
            let updated = try await VerifiedFindingsPatchExecutionService.execute(
                action: "prepare_patch",
                snapshot: snapshot,
                findingId: findingId,
                workspaceRoot: workspaceRoot,
                preferredProviderId: effectivePanelProviderId,
                providerRegistry: providerRegistry
            )
            await ingestUpdatedPatchSnapshot(updated)
            appendVerifiedFindingSystemMessage(
                sessionId: sessionId,
                findingId: findingId,
                title: "Patch pronta",
                detail: "La patch proposta e il diff preview sono ora disponibili prima dell'apply."
            )
        } catch {
            await markPatchFailure(
                sessionId: sessionId,
                findingId: findingId,
                message: error.localizedDescription
            )
        }
    }

    func applyPatch(sessionId: String, findingId: String) async {
        guard let workspaceRoot = workspaceStore.activeWorkspacePaths.first?.path else {
            await markPatchFailure(
                sessionId: sessionId,
                findingId: findingId,
                message: ReviewPatchWorkflowError.missingWorkspace.localizedDescription
            )
            return
        }
        guard let artifact = patchesForSession(sessionId).first(where: { $0.findingId == findingId }) else {
            appendVerifiedFindingSystemMessage(
                sessionId: sessionId,
                findingId: findingId,
                title: "Prepara patch richiesta",
                detail:
                    "Usa «Prepara patch» per generare il diff. Apply Patch è disponibile quando la patch risulta verificata e pronta."
            )
            return
        }
        guard artifact.isReadyForUserApply else {
            appendVerifiedFindingSystemMessage(
                sessionId: sessionId,
                findingId: findingId,
                title: "Patch non pronta",
                detail:
                    "Completa «Prepara patch» o attendi la verifica del diff; Apply Patch si abilita con diff disponibile e verificato."
            )
            return
        }
        await applyPreparedPatch(sessionId: sessionId, artifact: artifact, workspaceRoot: workspaceRoot)
    }

    func startBugHunterUncommitted() {
        guard let gitRoot = workspaceStore.activeWorkspacePaths.first?.path else { return }
        let runId = "bughunter-panel-\(UUID().uuidString.lowercased())"
        _ = MCPSharedState.enqueueBugHunterCommand(
            action: "start",
            runId: runId,
            conversationId: conversationId,
            payload: [
                "source_kind": MCPSharedBugHunterSourceKind.uncommitted.rawValue,
                "trigger_kind": MCPSharedBugHunterTriggerKind.manual.rawValue,
                "git_root": gitRoot,
            ]
        )
        MCPSharedState.writeBugHunterSnapshot(
            MCPSharedBugHunterSnapshot(
                runId: runId,
                conversationId: conversationId?.uuidString.lowercased(),
                sourceKind: .uncommitted,
                triggerKind: .manual,
                gitRoot: gitRoot,
                branchName: currentGitBranch,
                status: .queued,
                lastMessage: "Queued from review panel",
                autoFixMode: bugHunterSettings.autofixMode.rawValue,
                pipelinePhase: "queued",
                progressPercent: 0,
                stepsTotal: 6,
                stepsCompleted: 0,
                toolsTotal: 3,
                toolsCompleted: 0,
                toolsRunning: 0,
                verificationGateReady: false,
                patchGateReady: false,
                bundleModes: ["standard", "bugFinder", "securityAudit"],
                publishReady: false
            )
        )
        appendPanelSystemMessage(
            "BugHunter queued on uncommitted changes.",
            kind: .statusNote
        )
    }

    func startBugHunterCommitWindow() {
        guard let primaryCommit = selectedCommits.first ?? gitCommitLog.first?.sha,
              let gitRoot = workspaceStore.activeWorkspacePaths.first?.path else { return }
        let runId = "bughunter-window-\(UUID().uuidString.lowercased())"
        _ = MCPSharedState.enqueueBugHunterCommand(
            action: "start",
            runId: runId,
            conversationId: conversationId,
            payload: [
                "source_kind": MCPSharedBugHunterSourceKind.commitWindow.rawValue,
                "trigger_kind": MCPSharedBugHunterTriggerKind.manual.rawValue,
                "git_root": gitRoot,
                "primary_commit": primaryCommit,
                "branch_name": currentGitBranch,
            ]
        )
        appendPanelSystemMessage(
            "BugHunter queued on commit window \(primaryCommit.prefix(8)).",
            kind: .statusNote
        )
    }

    func applyPreparedPatch(
        sessionId: String,
        artifact: ReviewPatchArtifact,
        workspaceRoot: String
    ) async {
        do {
            let snapshot = patchWorkflowSnapshot(sessionId: sessionId, workspaceRoot: workspaceRoot)
            let updated = try await VerifiedFindingsPatchExecutionService.execute(
                action: "apply_patch",
                snapshot: snapshot,
                findingId: artifact.findingId,
                workspaceRoot: workspaceRoot,
                preferredProviderId: effectivePanelProviderId,
                providerRegistry: providerRegistry
            )
            await ingestUpdatedPatchSnapshot(updated)
            appendVerifiedFindingSystemMessage(
                sessionId: sessionId,
                findingId: artifact.findingId,
                title: "Patch applicata",
                detail: "Il fix è stato applicato e il lifecycle ora espone apply, validation e rollback."
            )
            if settings.autoOpenPRAfterApply {
                await openPatchPullRequest(sessionId: sessionId, findingId: artifact.findingId)
            }
        } catch {
            await markPatchFailure(
                sessionId: sessionId,
                findingId: artifact.findingId,
                message: error.localizedDescription
            )
        }
    }

    func ingestUpdatedPatchSnapshot(_ updated: CodeReviewSessionSnapshot) async {
        taskActivityStore.scheduleCodeReviewSnapshotIngest(updated, conversationId: conversationId)
    }

    func patchesForSession(_ sessionId: String) -> [ReviewPatchArtifact] {
        taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        )?.patches ?? []
    }

    func patchWorkflowSnapshot(
        sessionId: String,
        workspaceRoot: String
    ) -> CodeReviewSessionSnapshot {
        taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) ?? .init(
            sessionId: sessionId,
            conversationId: conversationId,
            phase: .idle,
            stage: .idle,
            findings: [],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: workspaceRoot,
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: nil,
            completedAt: nil,
            analysisCompletedAt: nil,
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: nil,
            lastUpdatedAt: Date()
        )
    }

    func markPatchFailure(
        sessionId: String,
        findingId: String,
        message: String
    ) async {
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else { return }
        if let reduced = reducePatchPrepareFailure(
            snapshot: snapshot,
            findingId: findingId,
            message: message
        ) {
            taskActivityStore.scheduleCodeReviewSnapshotIngest(reduced, conversationId: conversationId)
            appendVerifiedFindingSystemMessage(
                sessionId: sessionId,
                findingId: findingId,
                title: "Patch fallita",
                detail: message
            )
            return
        }
    }
}
