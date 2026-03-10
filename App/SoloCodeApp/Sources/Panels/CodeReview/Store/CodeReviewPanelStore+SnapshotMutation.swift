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

        let updated = snapshot.copying(
            findings: findings,
            events: snapshot.events + [event()],
            outcome: snapshot.copying(findings: findings).buildOutcomeSummary()
        )
        taskActivityStore.scheduleCodeReviewSnapshotIngest(
            updated,
            conversationId: conversationId
        )
    }
}
