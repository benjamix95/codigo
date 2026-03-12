import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func mutateLiveSessionUsingRust(
        sessionId: String,
        action: String,
        payload: [String: String]
    ) async -> Bool {
        guard let liveState = await ReviewSessionRegistry.shared.state(sessionId: sessionId) else {
            return false
        }
        let snapshot = await liveState.snapshot()
        guard let mutation: ReviewPanelCommandMutationResponse = ReviewCoreBridge.call(
            functionName: "review_core_command_mutate_snapshot",
            request: ReviewPanelCommandMutationRequest(
                schemaVersion: 1,
                action: action,
                snapshot: snapshot,
                payload: payload
            )
        ),
              !mutation.isError,
              let findings = mutation.findings,
              let events = mutation.events else {
            return false
        }

        let updated = snapshot.copying(
            findings: findings,
            events: events,
            outcome: snapshot.copying(findings: findings, events: events).buildOutcomeSummary()
        )
        await liveState.replaceCanonicalSnapshot(updated)
        await ReviewSessionRegistry.shared.recordSnapshot(updated)
        taskActivityStore.scheduleCodeReviewSnapshotIngest(
            updated,
            conversationId: conversationId
        )
        return true
    }

    func mutateSnapshotUsingRust(
        sessionId: String,
        action: String,
        payload: [String: String]
    ) async {
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else { return }

        guard let mutation: ReviewPanelCommandMutationResponse = ReviewCoreBridge.call(
            functionName: "review_core_command_mutate_snapshot",
            request: ReviewPanelCommandMutationRequest(
                schemaVersion: 1,
                action: action,
                snapshot: snapshot,
                payload: payload
            )
        ),
              !mutation.isError,
              let findings = mutation.findings,
              let events = mutation.events else {
            return
        }

        let updated = snapshot.copying(
            findings: findings,
            events: events,
            outcome: snapshot.copying(findings: findings).buildOutcomeSummary()
        )
        taskActivityStore.scheduleCodeReviewSnapshotIngest(
            updated,
            conversationId: conversationId
        )
    }
}

private struct ReviewPanelCommandMutationRequest: Encodable {
    let schemaVersion: Int
    let action: String
    let snapshot: CodeReviewSessionSnapshot
    let payload: [String: String]
}

private struct ReviewPanelCommandMutationResponse: Decodable {
    let isError: Bool
    let message: String?
    let findings: [CodeReviewFinding]?
    let events: [CodeReviewSessionEvent]?
}
