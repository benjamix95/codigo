import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func mutateSnapshot(
        sessionId: String,
        findingId: String,
        mutate: (inout CodeReviewFinding) -> Void,
        event: () -> CodeReviewSessionEvent
    ) async {
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else { return }

        var findings = snapshot.findings
        guard let index = findings.firstIndex(where: { $0.id == findingId }) else { return }
        mutate(&findings[index])

        let updated = CodeReviewSessionSnapshot(
            sessionId: snapshot.sessionId,
            conversationId: snapshot.conversationId,
            mutationSequence: snapshot.mutationSequence + 1,
            phase: snapshot.phase,
            stage: snapshot.stage,
            findings: findings,
            events: snapshot.events + [event()],
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
        taskActivityStore.ingestCodeReviewSnapshot(
            updated,
            conversationId: conversationId
        )
    }
}
