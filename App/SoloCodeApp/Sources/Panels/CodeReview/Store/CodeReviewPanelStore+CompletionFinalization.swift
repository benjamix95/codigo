import CoderEngine
import Foundation

extension CodeReviewPanelStore {
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
                current = current.copying(
                    findings: current.findings.map { finding in
                        guard finding.id == findingId else { return finding }
                        var updated = finding
                        updated.status = .patchFailed
                        updated.comments.append(
                            FindingComment(
                                author: "system",
                                content: "Patch preview non disponibile: \(error.localizedDescription)"
                            )
                        )
                        return updated
                    },
                    outcome: current.buildOutcomeSummary(
                        summaryOverride: "Patch preparation failed for \(findingId): \(error.localizedDescription)"
                    )
                )
                await ReviewSessionRegistry.shared.recordSnapshot(current)
                taskActivityStore.scheduleCodeReviewSnapshotIngest(
                    current,
                    conversationId: conversationId ?? current.conversationId
                )
            }
        }
        return current
    }
}
