import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func exportSummary(sessionId: String) -> String {
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else { return "No session found" }
        return ReviewPanelChatMessageFactory.summary(snapshot: snapshot).content
    }

    func publishSummaryToChat(sessionId: String) {
        guard settings.publishOutcomeToChat else { return }
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else { return }
        selectTab(.chat)
        appendChatMessage(ReviewPanelChatMessageFactory.summary(snapshot: snapshot))
    }
}
