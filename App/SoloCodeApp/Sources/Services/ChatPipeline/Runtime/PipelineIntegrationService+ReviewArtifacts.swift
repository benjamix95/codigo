import CoderEngine
import Foundation

extension PipelineIntegrationService {
    func handlePatchApplied(_ p: PatchAppliedPayload, for conversationId: UUID) {
        let patchRuntime = runtime(for: conversationId)
        for file in p.touchedFiles {
            consumePipelineEvents(
                [
                    ChatPipelineEvent(
                        conversationId: conversationId,
                        assistantMessageId: patchRuntime?.assistantMessageId ?? UUID(),
                        turnId: patchRuntime?.chatTurnState.turnId ?? UUID().uuidString,
                        sequence: 0,
                        source: "pipeline",
                        kind: .filesArtifact,
                        payload: ["path": file]
                    ),
                ],
                for: conversationId
            )
        }
    }

    func handleRollback(_ p: RollbackPayload, for conversationId: UUID) {
        let rollbackRuntime = runtime(for: conversationId)
        consumePipelineEvents(
            [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: rollbackRuntime?.assistantMessageId ?? UUID(),
                    turnId: rollbackRuntime?.chatTurnState.turnId ?? UUID().uuidString,
                    sequence: 0,
                    source: "pipeline",
                    kind: .statusBadge,
                    payload: [
                        "artifact_id": "rollback-\(p.taskId)",
                        "title": "Rollback triggered",
                        "detail": p.reason,
                    ]
                ),
            ],
            for: conversationId
        )
    }

    func handleReviewFinding(_ p: ReviewFindingPayload, for conversationId: UUID) {
        upsertInlineReviewFindingSession(p, for: conversationId)
        let reviewRuntime = runtime(for: conversationId)
        let snapshot = taskActivityStore?.codeReviewSnapshot(
            sessionId: inlineReviewSessionId(for: conversationId),
            conversationId: conversationId
        )
        let payload = snapshot.map {
            VerifiedFindingsChatPresentationService.mainChatArtifactPayload(
                payload: p,
                snapshot: $0
            )
        } ?? [
            "artifact_id": "review-finding-\(p.jobId)-\(p.taskId)-\(p.finding.findingId)",
            "title": "Review finding",
            "detail": "[\(p.finding.severity.rawValue.uppercased())] \(p.finding.file): \(p.finding.message)",
        ]

        consumePipelineEvents(
            [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: reviewRuntime?.assistantMessageId ?? UUID(),
                    turnId: reviewRuntime?.chatTurnState.turnId ?? UUID().uuidString,
                    sequence: 0,
                    source: "pipeline",
                    kind: .toolTraceArtifact,
                    payload: payload
                ),
            ],
            for: conversationId
        )
    }
}
