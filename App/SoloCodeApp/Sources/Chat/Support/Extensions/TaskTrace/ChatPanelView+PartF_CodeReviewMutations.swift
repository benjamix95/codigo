import CoderEngine
import Foundation

extension ChatPanelView {
    @MainActor
    func applyInlineReviewFixes(
        sessionId: String,
        findingIds: [String]
    ) async {
        guard let snapshot = selectedCodeReviewSnapshot(sessionId: sessionId) else { return }
        let findings = snapshot.findings.filter { findingIds.contains($0.id) }
        guard !findings.isEmpty else { return }
        dispatchCodeReviewPrompt(
            CodeReviewPromptBuilder.targetedFixPrompt(
                snapshot: snapshot,
                findings: findings,
                targetSessionId: snapshot.sessionId
            ),
            sessionConfigOverride: snapshot.config
        )
    }

    @MainActor
    func dismissInlineReviewFindings(
        sessionId: String,
        findingIds: [String],
        reason: String
    ) async {
        if let liveState = await ReviewSessionRegistry.shared.state(sessionId: sessionId) {
            var didChange = false
            for findingId in findingIds {
                didChange = await liveState.dismissFinding(
                    findingId: findingId,
                    reason: reason
                ) || didChange
            }
            if didChange {
                await persistReviewSnapshotForPanel(await liveState.snapshot())
            }
            return
        }

        guard let snapshot = selectedCodeReviewSnapshot(sessionId: sessionId) else { return }
        let status: FindingStatus = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == FindingStatus.wontFix.rawValue ? .wontFix : .dismissed
        let updatedFindings = snapshot.findings.map { finding in
            guard findingIds.contains(finding.id) else { return finding }
            var updated = finding
            updated.status = status
            return updated
        }
        let changedCount = zip(snapshot.findings, updatedFindings)
            .filter { $0.status != $1.status }
            .count
        guard changedCount > 0 else { return }

        let updatedSnapshot = CodeReviewSessionSnapshot(
            sessionId: snapshot.sessionId,
            conversationId: snapshot.conversationId,
            mutationSequence: snapshot.mutationSequence + 1,
            phase: snapshot.phase,
            stage: snapshot.stage,
            findings: updatedFindings,
            events: snapshot.events + findingIds.map {
                CodeReviewSessionEvent.findingDismissed(findingId: $0, reason: reason)
            },
            config: snapshot.config,
            scope: snapshot.scope,
            workspacePath: snapshot.workspacePath,
            currentRound: snapshot.currentRound,
            activeWorkerCount: snapshot.activeWorkerCount,
            startedAt: snapshot.startedAt,
            completedAt: snapshot.completedAt,
            analysisCompletedAt: snapshot.analysisCompletedAt,
            lastError: snapshot.lastError,
            currentJobId: snapshot.currentJobId,
            lastTestStatus: snapshot.lastTestStatus,
            lastUpdatedAt: Date()
        )
        await persistReviewSnapshotForPanel(updatedSnapshot)
    }

    @MainActor
    func persistReviewSnapshotForPanel(_ snapshot: CodeReviewSessionSnapshot) async {
        await ReviewSessionRegistry.shared.recordSnapshot(snapshot)
        taskActivityStore.ingestCodeReviewSnapshot(
            snapshot,
            conversationId: conversationId ?? snapshot.conversationId
        )
    }

    @MainActor
    func selectedCodeReviewSnapshot(sessionId: String) -> CodeReviewSessionSnapshot? {
        taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        )
    }
}
