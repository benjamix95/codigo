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
        ), let finding = snapshot.findings.first(where: { $0.id == findingId }),
        let workspaceRoot = workspaceStore.activeWorkspacePaths.first?.path else {
            return
        }

        let service = ReviewPatchWorkflowService()
        do {
            let artifact = try await service.preparePatch(
                finding: finding,
                snapshot: snapshot,
                preferredProviderId: effectivePanelProviderId,
                providerRegistry: providerRegistry,
                workspaceRoot: workspaceRoot
            )
            await upsertPatchArtifact(sessionId: sessionId, artifact: artifact)
            appendPanelSystemMessage(
                "Patch pronta e validata per finding \(findingId).",
                kind: .findingMutation,
                selectChatTab: false
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
            await preparePatch(sessionId: sessionId, findingId: findingId)
            guard let prepared = patchesForSession(sessionId).first(where: { $0.findingId == findingId }) else { return }
            await applyPreparedPatch(sessionId: sessionId, artifact: prepared, workspaceRoot: workspaceRoot)
            return
        }
        await applyPreparedPatch(sessionId: sessionId, artifact: artifact, workspaceRoot: workspaceRoot)
    }

    func openPatchPullRequest(sessionId: String, findingId: String) async {
        guard let artifact = currentPatches.first(where: { $0.findingId == findingId }),
              let workspaceRoot = workspaceStore.activeWorkspacePaths.first?.path,
              let finding = currentFindings.first(where: { $0.id == findingId }) else {
            return
        }

        let title = "fix(review): \(finding.filePath.components(separatedBy: "/").last ?? finding.filePath)"
        let body = """
        Review finding: \(finding.id)

        \(finding.message)

        Verification:
        \(finding.verificationReport ?? "n/a")
        """

        let service = ReviewPatchWorkflowService()
        do {
            let opened = try service.openPullRequest(
                artifact: artifact,
                title: title,
                body: body,
                workspaceRoot: workspaceRoot
            )
            await upsertPatchArtifact(sessionId: sessionId, artifact: opened)
            appendPanelSystemMessage(
                "PR aperta per finding \(findingId): \(opened.prURL ?? "n/a")",
                kind: .statusNote,
                selectChatTab: true
            )
        } catch {
            await markPatchFailure(sessionId: sessionId, findingId: findingId, message: error.localizedDescription)
        }
    }

    func mergePatchPullRequest(sessionId: String, findingId: String) async {
        guard let artifact = currentPatches.first(where: { $0.findingId == findingId }),
              let workspaceRoot = workspaceStore.activeWorkspacePaths.first?.path else {
            return
        }
        let service = ReviewPatchWorkflowService()
        do {
            let merged = try await service.mergePullRequest(
                artifact: artifact,
                preferredProviderId: effectivePanelProviderId,
                providerRegistry: providerRegistry,
                workspaceRoot: workspaceRoot,
                safeOnly: settings.autoResolveConflicts == .safeOnly
            )
            await upsertPatchArtifact(sessionId: sessionId, artifact: merged)
            appendPanelSystemMessage(
                "Merge completato per finding \(findingId).",
                kind: .statusNote,
                selectChatTab: true
            )
        } catch {
            await markPatchFailure(sessionId: sessionId, findingId: findingId, message: error.localizedDescription)
        }
    }

    private func applyPreparedPatch(
        sessionId: String,
        artifact: ReviewPatchArtifact,
        workspaceRoot: String
    ) async {
        let service = ReviewPatchWorkflowService()
        do {
            let verified = try await service.verifyPatch(artifact: artifact, workspaceRoot: workspaceRoot)
            let applied = try await service.applyPatch(artifact: verified, workspaceRoot: workspaceRoot)
            await upsertPatchArtifact(sessionId: sessionId, artifact: applied)
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

    private func upsertPatchArtifact(
        sessionId: String,
        artifact: ReviewPatchArtifact
    ) async {
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else { return }
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

        let updated = snapshot.copying(
            findings: findings,
            patches: patches,
            events: snapshot.events + [CodeReviewSessionEvent.patchPrepared(patchId: artifact.id, findingId: artifact.findingId)],
            outcome: snapshot.copying(findings: findings, patches: patches).buildOutcomeSummary()
        )
        taskActivityStore.ingestCodeReviewSnapshot(updated, conversationId: conversationId)
    }

    private func patchesForSession(_ sessionId: String) -> [ReviewPatchArtifact] {
        taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        )?.patches ?? []
    }

    private func markPatchFailure(
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
            outcome: snapshot.copying(findings: findings, patches: patches).buildOutcomeSummary(summaryOverride: message)
        )
        taskActivityStore.ingestCodeReviewSnapshot(updated, conversationId: conversationId)
        appendPanelSystemMessage(
            "Patch fallita per finding \(findingId): \(message)",
            kind: .statusNote,
            selectChatTab: true
        )
    }
}
