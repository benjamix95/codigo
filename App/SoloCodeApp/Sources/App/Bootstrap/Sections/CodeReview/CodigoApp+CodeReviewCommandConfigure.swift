import CoderEngine
import Foundation

extension CodigoApp {
    @MainActor
    func configuredReviewSnapshot(
        snapshot: CodeReviewSessionSnapshot,
        sessionId: String,
        conversationId: UUID?,
        config: SessionConfig
    ) -> CodeReviewSessionSnapshot? {
        let payload = ["session_id": sessionId]
            .merging(config.reviewCommandPayload) { _, rhs in rhs }
        guard let mutation = ReviewCommandRustBridge.mutateSnapshot(
            snapshot,
            action: "configure",
            payload: payload
        ),
              !mutation.isError,
              let updatedConfig = mutation.config,
              let events = mutation.events else {
            return nil
        }
        let updated = snapshot.copying(
            events: events,
            config: updatedConfig
        )
        return updated.copying(
            mutationSequence: updated.mutationSequence,
            outcome: updated.buildOutcomeSummary(),
            lastUpdatedAt: Date()
        )
    }
}
