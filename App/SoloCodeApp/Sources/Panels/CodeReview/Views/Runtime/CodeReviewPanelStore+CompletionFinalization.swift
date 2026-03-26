import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func applyFix(sessionId: String, findingId: String) async {
        await applyPatch(sessionId: sessionId, findingId: findingId)
    }

    func dismissFinding(
        sessionId: String,
        findingId: String,
        reason: String
    ) async {
        let status: FindingStatus = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == FindingStatus.wontFix.rawValue ? .wontFix : .dismissed
        if await ReviewSessionRegistry.shared.dismissFinding(
            sessionId: sessionId,
            findingId: findingId,
            reason: status == .wontFix ? FindingStatus.wontFix.rawValue : reason
        ) {
            if let snapshot = await ReviewSessionRegistry.shared.snapshot(sessionId: sessionId) {
                taskActivityStore.ingestCodeReviewSnapshot(
                    snapshot,
                    conversationId: conversationId
                )
            }
            appendPanelSystemMessage(
                "Finding \(findingId) dismissed (\(reason)).",
                kind: .findingMutation
            )
            return
        }
        await mutateSnapshotUsingRust(
            sessionId: sessionId,
            action: "dismiss",
            payload: [
                "finding_id": findingId,
                "reason": status == .wontFix ? FindingStatus.wontFix.rawValue : reason,
            ]
        )
        appendPanelSystemMessage(
            "Finding \(findingId) dismissed (\(reason)).",
            kind: .findingMutation
        )
    }

    func applyAllFixes(sessionId: String, findingIds: [String]) async {
        guard let sourceSnapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else {
            return
        }
        let readyIds = findingIds.filter { fid in
            sourceSnapshot.patches.contains {
                $0.findingId == fid && $0.isReadyForUserApply
            }
        }
        guard !readyIds.isEmpty else {
            if !findingIds.isEmpty {
                appendPanelSystemMessage(
                    "Fix All: nessuna patch pronta tra i finding selezionati. Per ciascuno: verifica il bug, prepara la patch e attendi diff verificato.",
                    kind: .statusNote
                )
            }
            return
        }

        for findingId in readyIds {
            await applyPatch(sessionId: sessionId, findingId: findingId)
        }

        let skipped = findingIds.count - readyIds.count
        if skipped > 0 {
            appendPanelSystemMessage(
                "Fix All: applicate \(readyIds.count) patch pronte; \(skipped) finding saltati (patch assente o non ancora verificata).",
                kind: .statusNote
            )
        }
    }

    func dismissAll(
        sessionId: String,
        findingIds: [String],
        reason: String
    ) async {
        for fid in findingIds {
            await dismissFinding(
                sessionId: sessionId, findingId: fid, reason: reason
            )
        }
    }

    func patchFinalizationTargets(
        for snapshot: CodeReviewSessionSnapshot
    ) -> [String]? {
        let response: ReviewPanelPatchFinalizationTargetsResponse? = ReviewCoreBridge.call(
            functionName: "review_core_reduce_panel_state",
            request: ReviewPanelPatchFinalizationTargetsRequest(
                schemaVersion: 1,
                operation: "derive_patch_finalization_targets",
                snapshot: snapshot
            )
        )
        guard response?.error == nil else { return nil }
        return response?.panelState
    }

    func finalizeCompletedReviewSessionIfNeeded(
        snapshot: CodeReviewSessionSnapshot
    ) async -> CodeReviewSessionSnapshot {
        guard snapshot.phase == .completed else { return snapshot }
        guard let workspaceRoot = snapshot.workspacePath ?? workspaceStore.activeWorkspacePaths.first?.path else {
            return snapshot
        }

        let targetIds = patchFinalizationTargets(for: snapshot) ?? snapshot.findings.compactMap { finding -> String? in
            let isVerified = finding.verifiedAt != nil || finding.verificationReport != nil
            guard isVerified else { return nil }
            let patch = snapshot.patches.first(where: { $0.findingId == finding.id })
            if let patch, patch.verifyStatus == .verified, [.verified, .applied, .prOpened, .merged].contains(patch.status) {
                return nil
            }
            return finding.id
        }

        guard !targetIds.isEmpty else { return snapshot }

        var current = snapshot
        guard let runtimeProvider = effectivePanelProvider
            ?? providerRegistry.provider(for: effectivePanelProviderId ?? "")
            ?? providerRegistry.selectedProvider
            ?? providerRegistry.providers.first else {
            return snapshot
        }
        for findingId in targetIds {
            do {
                current = try await ReviewPatchRuntimeFinalizationService.prepareVerifiedPatches(
                    snapshot: current,
                    findingIds: [findingId],
                    workspaceRoot: workspaceRoot,
                    executionProvider: runtimeProvider
                )
                await ReviewSessionRegistry.shared.recordSnapshot(current)
                taskActivityStore.scheduleCodeReviewSnapshotIngest(
                    current,
                    conversationId: conversationId ?? current.conversationId
                )
            } catch {
                guard let reduced = reducePatchPrepareFailure(
                    snapshot: current,
                    findingId: findingId,
                    message: error.localizedDescription
                ) else {
                    continue
                }
                current = reduced
                await ReviewSessionRegistry.shared.recordSnapshot(current)
                taskActivityStore.scheduleCodeReviewSnapshotIngest(
                    current,
                    conversationId: conversationId ?? current.conversationId
                )
            }
        }
        return current
    }

    func freezeTimer() {
        guard let start = runStartedAt else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        frozenTimerText = String(format: "%d:%02d", minutes, seconds)
    }

    private func snapshot(for sessionId: String?) -> CodeReviewSessionSnapshot? {
        guard let sessionId else { return nil }
        return taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        )
    }

    func historyLiveFiles(from card: SwarmLiveCardState) -> [String] {
        Array(Set(card.recentEvents.compactMap { event -> [String]? in
            let raw = event.payload["files_raw"] ?? event.payload["files"]
            guard let raw, !raw.isEmpty else { return nil }
            return raw.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }.flatMap { $0 })).sorted()
    }

    func historyLiveWorkerId(for card: SwarmLiveCardState) -> String? {
        if !card.swarmId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return card.swarmId
        }
        return card.recentEvents.compactMap { $0.payload["worker_id"] }.first
    }
}

private struct ReviewPanelPatchFinalizationTargetsRequest: Encodable {
    let schemaVersion: Int
    let operation: String
    let snapshot: CodeReviewSessionSnapshot
}

private struct ReviewPanelPatchFinalizationTargetsResponse: Decodable {
    let schemaVersion: Int
    let error: ReviewPanelReduceError?
    let panelState: [String]?
}
