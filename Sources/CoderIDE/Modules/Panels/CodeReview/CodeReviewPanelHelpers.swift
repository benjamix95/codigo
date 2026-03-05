import Foundation

func isValidGitRefFormat(_ ref: String) -> Bool {
    let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    guard !trimmed.hasPrefix("-") else { return false }
    guard !trimmed.hasSuffix(".lock") else { return false }
    guard !trimmed.hasSuffix(".") else { return false }
    let invalidChars = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
    guard trimmed.unicodeScalars.allSatisfy({ !invalidChars.contains($0) }) else { return false }
    let forbidden = [":", "?", "*", "[", "\\", "@{"]
    for seq in forbidden { if trimmed.contains(seq) { return false } }
    return true
}

func latestReviewWorkerPlanBatch(in activities: [TaskActivity]) -> [TaskActivity] {
    guard let lastPlanIndex = activities.lastIndex(where: { $0.type == "review-worker-plan" }) else {
        return []
    }

    var firstPlanIndex = lastPlanIndex
    while firstPlanIndex > activities.startIndex {
        let previousIndex = activities.index(before: firstPlanIndex)
        guard activities[previousIndex].type == "review-worker-plan" else {
            break
        }
        firstPlanIndex = previousIndex
    }

    return Array(activities[firstPlanIndex...lastPlanIndex])
}

func scopedTaskActivitiesForConversation(
    _ activities: [TaskActivity],
    conversationId: UUID?
) -> [TaskActivity] {
    guard let conversationId else { return activities }
    let expected = conversationId.uuidString.lowercased()
    return activities.filter { activity in
        canonicalConversationScope(from: activity.payload) == expected
    }
}

func reviewCardBelongsToConversation(
    _ card: SwarmLiveCardState,
    conversationId: UUID?
) -> Bool {
    guard conversationId != nil else { return true }
    guard !card.recentEvents.isEmpty else { return false }
    return !scopedTaskActivitiesForConversation(card.recentEvents, conversationId: conversationId).isEmpty
}

func sortedReviewWorkerPlanActivitiesForDisplay(_ activities: [TaskActivity]) -> [TaskActivity] {
    activities.sorted { lhs, rhs in
        let lhsWorkerID = (lhs.payload["worker_id"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsWorkerID = (rhs.payload["worker_id"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lhsHasWorker = !lhsWorkerID.isEmpty
        let rhsHasWorker = !rhsWorkerID.isEmpty

        if lhsHasWorker && rhsHasWorker && lhsWorkerID != rhsWorkerID {
            return lhsWorkerID.localizedStandardCompare(rhsWorkerID) == .orderedAscending
        }
        if lhsHasWorker != rhsHasWorker {
            return lhsHasWorker
        }
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

func selectReviewWorkerActivities(from activities: [TaskActivity]) -> [TaskActivity] {
    guard !activities.isEmpty else { return [] }

    if let boundary = activities.lastIndex(where: { $0.type == "review-fix-round" }) {
        let after = Array(activities[(activities.index(after: boundary))...])
        let plansAfterBoundary = latestReviewWorkerPlanBatch(in: after)
        if !plansAfterBoundary.isEmpty {
            return plansAfterBoundary
        }

        let upToBoundary = Array(activities[...boundary])
        return latestReviewWorkerPlanBatch(in: upToBoundary)
    }

    return latestReviewWorkerPlanBatch(in: activities)
}
