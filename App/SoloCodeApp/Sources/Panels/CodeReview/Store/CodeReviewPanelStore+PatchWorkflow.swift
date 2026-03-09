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
        ), snapshot.findings.contains(where: { $0.id == findingId }),
        let workspaceRoot = workspaceStore.activeWorkspacePaths.first?.path else {
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

    func revalidatePatch(sessionId: String, findingId: String) async {
        guard let workspaceRoot = workspaceStore.activeWorkspacePaths.first?.path else {
            await markPatchFailure(
                sessionId: sessionId,
                findingId: findingId,
                message: ReviewPatchWorkflowError.missingWorkspace.localizedDescription
            )
            return
        }
        guard patchesForSession(sessionId).contains(where: { $0.findingId == findingId }) else {
            await markPatchFailure(
                sessionId: sessionId,
                findingId: findingId,
                message: ReviewPatchWorkflowError.invalidPatch.localizedDescription
            )
            return
        }
        do {
            let snapshot = patchWorkflowSnapshot(sessionId: sessionId, workspaceRoot: workspaceRoot)
            let updated = try await VerifiedFindingsPatchExecutionService.execute(
                action: "revalidate_finding",
                snapshot: snapshot,
                findingId: findingId,
                workspaceRoot: workspaceRoot,
                preferredProviderId: effectivePanelProviderId,
                providerRegistry: providerRegistry
            )
            await ingestUpdatedPatchSnapshot(updated)
            appendPanelSystemMessage(
                "Revalidation completata per finding \(findingId).",
                kind: .statusNote,
                selectChatTab: false
            )
        } catch {
            await markPatchFailure(sessionId: sessionId, findingId: findingId, message: error.localizedDescription)
        }
    }

    func rollbackPatch(sessionId: String, findingId: String) async {
        guard let workspaceRoot = workspaceStore.activeWorkspacePaths.first?.path else {
            await markPatchFailure(
                sessionId: sessionId,
                findingId: findingId,
                message: ReviewPatchWorkflowError.missingWorkspace.localizedDescription
            )
            return
        }
        guard patchesForSession(sessionId).contains(where: { $0.findingId == findingId }) else {
            await markPatchFailure(
                sessionId: sessionId,
                findingId: findingId,
                message: ReviewPatchWorkflowError.invalidPatch.localizedDescription
            )
            return
        }
        do {
            let snapshot = patchWorkflowSnapshot(sessionId: sessionId, workspaceRoot: workspaceRoot)
            let updated = try await VerifiedFindingsPatchExecutionService.execute(
                action: "rollback_patch",
                snapshot: snapshot,
                findingId: findingId,
                workspaceRoot: workspaceRoot,
                preferredProviderId: effectivePanelProviderId,
                providerRegistry: providerRegistry
            )
            await ingestUpdatedPatchSnapshot(updated)
            appendPanelSystemMessage(
                "Rollback completato per finding \(findingId).",
                kind: .statusNote,
                selectChatTab: true
            )
        } catch {
            await markPatchFailure(sessionId: sessionId, findingId: findingId, message: error.localizedDescription)
        }
    }

    func openPatchPullRequest(sessionId: String, findingId: String) async {
        guard currentPatches.contains(where: { $0.findingId == findingId }),
              let workspaceRoot = workspaceStore.activeWorkspacePaths.first?.path,
              currentFindings.contains(where: { $0.id == findingId }) else {
            return
        }

        do {
            let snapshot = patchWorkflowSnapshot(sessionId: sessionId, workspaceRoot: workspaceRoot)
            let updated = try await VerifiedFindingsPatchExecutionService.execute(
                action: "open_pr",
                snapshot: snapshot,
                findingId: findingId,
                workspaceRoot: workspaceRoot,
                preferredProviderId: effectivePanelProviderId,
                providerRegistry: providerRegistry
            )
            await ingestUpdatedPatchSnapshot(updated)
            appendPanelSystemMessage(
                "PR aperta per finding \(findingId): \(updated.patches.first(where: { $0.findingId == findingId })?.prURL ?? "n/a")",
                kind: .statusNote,
                selectChatTab: true
            )
        } catch {
            await markPatchFailure(sessionId: sessionId, findingId: findingId, message: error.localizedDescription)
        }
    }

    func mergePatchPullRequest(sessionId: String, findingId: String) async {
        guard currentPatches.contains(where: { $0.findingId == findingId }),
              let workspaceRoot = workspaceStore.activeWorkspacePaths.first?.path else {
            return
        }
        do {
            let snapshot = patchWorkflowSnapshot(sessionId: sessionId, workspaceRoot: workspaceRoot)
            let updated = try await VerifiedFindingsPatchExecutionService.execute(
                action: "merge_pr",
                snapshot: snapshot,
                findingId: findingId,
                workspaceRoot: workspaceRoot,
                preferredProviderId: effectivePanelProviderId,
                providerRegistry: providerRegistry
            )
            await ingestUpdatedPatchSnapshot(updated)
            appendPanelSystemMessage(
                "Merge completato per finding \(findingId).",
                kind: .statusNote,
                selectChatTab: true
            )
        } catch {
            await markPatchFailure(sessionId: sessionId, findingId: findingId, message: error.localizedDescription)
        }
    }
}
