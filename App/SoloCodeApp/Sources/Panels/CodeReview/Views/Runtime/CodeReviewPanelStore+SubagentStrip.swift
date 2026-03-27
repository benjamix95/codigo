import Foundation

extension CodeReviewPanelStore {
    /// Card swarm live legate alla review della sessione (stessi criteri del tab History → live cards).
    var reviewSubagentLiveCards: [SwarmLiveCardState] {
        let sessionId = selectedSessionId
        return taskActivityStore
            .swarmCardStatesIncludingPending(for: conversationId)
            .filter { isCodeReviewSwarmCard($0) && reviewCardBelongsToSession($0, sessionId: sessionId) }
    }

    #if DEBUG
    /// Perché la strip “Live activity” resta vuota: confronto card swarm totali vs filtro review/session.
    func emitReviewSubagentStripDiagnostics(reason: String) {
        let conv = conversationId
        let sessionId = selectedSessionId
        let all = taskActivityStore.swarmCardStatesIncludingPending(for: conv)
        let cr = all.filter { isCodeReviewSwarmCard($0) }
        let matched = cr.filter { reviewCardBelongsToSession($0, sessionId: sessionId) }
        let convKey = conv?.uuidString.lowercased() ?? ""
        let reviewishActivities = taskActivityStore.activities.filter { a in
            let scope = canonicalConversationScope(from: a.payload) ?? ""
            if !scope.isEmpty, scope != convKey { return false }
            let t = a.type.lowercased()
            return t.contains("subagent")
                || t == "review-worker-plan"
                || t == "review-fix-round"
                || t == "code_review_update"
        }
        let sampleSwarm = all.prefix(4).map(\.swarmId).joined(separator: ",")
        ReviewPanelDebugNDJSON.emitThrottled(
            key: "subagentStripDiag",
            minInterval: 0.55,
            hypothesisId: "H_strip_diag",
            location: "CodeReviewPanelStore.emitReviewSubagentStripDiagnostics",
            message: "strip_swarm_diag",
            data: [
                "reason": reason,
                "conversationScoped": convKey,
                "selectedSessionId": sessionId ?? "",
                "allSwarmCards": all.count,
                "codeReviewTaggedCards": cr.count,
                "afterSessionFilter": matched.count,
                "reviewishActivityCount": reviewishActivities.count,
                "sampleSwarmIds": sampleSwarm,
            ]
        )
    }
    #endif
}
