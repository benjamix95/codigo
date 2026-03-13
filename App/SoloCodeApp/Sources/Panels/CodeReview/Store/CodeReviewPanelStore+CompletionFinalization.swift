import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    @MainActor
    func normalizedPanelChatUserMessage(
        _ userMessage: String,
        selectedSessionId: String?
    ) -> String {
        guard let selectedSessionId,
              makeAutoCodeReviewRequest(
                userText: userMessage,
                coderMode: .agent
              ).prefersCodeReviewRuntimeProvider else {
            return userMessage
        }

        return """
        Treat the request as analysis over the CURRENT active review session.
        Reuse session_id \(selectedSessionId) and the current findings context.
        Do NOT call review_start or create a new review session unless the user explicitly asks for a new session or a new run.
        If more evidence is needed, inspect files directly and update findings within the current session.

        User request:
        \(userMessage)
        """
    }

    func buildChatPrompt(
        userMessage: String,
        sessionId: String? = nil
    ) -> String {
        let snapshot = snapshot(for: sessionId)
        let findingsCount = snapshot?.findings.count ?? 0
        let openCount = snapshot?.findings.filter { $0.status == .open }.count ?? 0
        let candidateCount = snapshot?.candidates.count ?? 0
        let patchCount = snapshot?.patches.count ?? 0

        var summary = "Phase: \(snapshot?.phase.rawValue ?? "none")"
        if let scope = snapshot?.scope {
            summary += "\nScope: \(scope.description)"
        }
        summary += "\nCandidates: \(candidateCount)"
        summary += "\nPatches: \(patchCount)"
        if findingsCount > 0 {
            let critCount = snapshot?.findings
                .filter { $0.severity == .critical }.count ?? 0
            let warnCount = snapshot?.findings
                .filter { $0.severity == .warning }.count ?? 0
            summary += "\nFindings breakdown: \(critCount) critical, \(warnCount) warning"
        }

        let findingsContext: String
        if let findings = snapshot?.findings.prefix(10), !findings.isEmpty {
            let lines = findings.map { f in
                let line = f.lineNumber.map { ":\($0)" } ?? ""
                return "[\(f.severity.rawValue)] \(f.filePath)\(line) - \(f.message)"
            }
            findingsContext = "\nRecent findings:\n" + lines.joined(separator: "\n")
        } else {
            findingsContext = ""
        }

        return ReviewPanelCoordinator.chatContextPrompt(
            userMessage: userMessage,
            sessionSummary: summary + findingsContext,
            findingsCount: findingsCount,
            openCount: openCount,
            activeSessionId: sessionId ?? selectedSessionId,
            conversationId: conversationId
        )
    }

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
                taskActivityStore.scheduleCodeReviewSnapshotIngest(
                    snapshot,
                    conversationId: conversationId
                )
            }
            appendPanelSystemMessage(
                "Finding \(findingId) dismissed (\(reason)).",
                kind: .findingMutation,
                selectChatTab: false
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
            kind: .findingMutation,
            selectChatTab: false
        )
    }

    func applyAllFixes(sessionId: String, findingIds: [String]) async {
        guard let sourceSnapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else {
            return
        }
        let findings = sourceSnapshot.findings.filter { findingIds.contains($0.id) }
        guard !findings.isEmpty else { return }

        for finding in findings {
            await applyPatch(sessionId: sessionId, findingId: finding.id)
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
