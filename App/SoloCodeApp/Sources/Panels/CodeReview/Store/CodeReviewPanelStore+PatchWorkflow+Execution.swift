import CoderEngine
import Foundation

extension CodeReviewPanelStore {
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
            appendPanelSystemMessage(
                "Patch applicata per finding \(artifact.findingId).",
                kind: .findingMutation,
                selectChatTab: false
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
        taskActivityStore.ingestCodeReviewSnapshot(updated, conversationId: conversationId)
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
        var findings = snapshot.findings
        var patches = snapshot.patches
        if let index = findings.firstIndex(where: { $0.id == findingId }) {
            findings[index].status = .patchFailed
        }
        if let patchIndex = patches.firstIndex(where: { $0.findingId == findingId }) {
            patches[patchIndex].status = .applyFailed
            patches[patchIndex].verifyStatus = .failed
            patches[patchIndex].applyMessage = message
            patches[patchIndex].conflicts = [message]
            patches[patchIndex].updatedAt = Date()
        }
        let updated = snapshot.copying(
            findings: findings,
            patches: patches,
            events: snapshot.events + [
                CodeReviewSessionEvent(
                    type: .patchApplyFailed,
                    detail: message,
                    metadata: ["finding_id": findingId]
                ),
            ],
            outcome: snapshot.copying(findings: findings, patches: patches)
                .buildOutcomeSummary(summaryOverride: message)
        )
        taskActivityStore.ingestCodeReviewSnapshot(updated, conversationId: conversationId)
        appendPanelSystemMessage(
            "Patch fallita per finding \(findingId): \(message)",
            kind: .statusNote,
            selectChatTab: true
        )
    }
}
