import Foundation

extension CodeReviewPanelStore {
    /// Card swarm live legate alla review della sessione (stessi criteri del tab History → live cards).
    var reviewSubagentLiveCards: [SwarmLiveCardState] {
        let sessionId = selectedSessionId
        return taskActivityStore
            .swarmCardStatesIncludingPending(for: conversationId)
            .filter { isCodeReviewSwarmCard($0) && reviewCardBelongsToSession($0, sessionId: sessionId) }
    }
}
