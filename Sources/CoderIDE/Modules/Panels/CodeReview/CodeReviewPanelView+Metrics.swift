import Foundation

extension CodeReviewPanelView {
    func metrics() -> CodeReviewMetrics {
        let activities = scopedTaskActivitiesForConversation(
            taskActivityStore.activities,
            conversationId: conversationId
        )
        let cards = taskActivityStore
            .swarmCardStates(for: conversationId)
            .filter {
                $0.swarmId.hasPrefix("review-")
                    && reviewCardBelongsToConversation($0, conversationId: conversationId)
            }
        let active = cards.filter { $0.status == .running }.count

        let workerActivities = sortedReviewWorkerPlanActivitiesForDisplay(
            selectReviewWorkerActivities(from: activities)
        )
        let hasReviewArtifacts = hasCodeReviewArtifacts(
            cards: cards,
            workerActivities: workerActivities,
            activities: activities
        )
        guard shouldDisplayCodeReviewMetrics(
            coderMode: coderMode,
            hasReviewArtifacts: hasReviewArtifacts
        ) else {
            return CodeReviewMetrics(cards: [], activeCount: 0, workers: [], roundInfo: nil)
        }

        let workers: [ReviewWorkerRow] = workerActivities.compactMap { a in
            guard let wid = a.payload["worker_id"],
                  let desc = a.payload["description"],
                  let sev = a.payload["severity"],
                  let fcRaw = a.payload["fileCount"] else { return nil }
            let fileCount = Int(fcRaw) ?? 0
            let summary = a.payload["files"] ?? ""
            let rawFiles = (a.payload["files_raw"] ?? "")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return ReviewWorkerRow(
                id: wid,
                description: desc,
                severity: sev,
                fileCount: fileCount,
                files: rawFiles,
                filesSummary: summary
            )
        }

        let round: (String, String)? = if hasReviewArtifacts {
            activities.reversed().compactMap { a -> (String, String)? in
                guard a.type == "review-fix-round",
                      let r = a.payload["round"],
                      let m = a.payload["maxRounds"] else { return nil }
                return (r, m)
            }.first
        } else { nil }

        return CodeReviewMetrics(cards: cards, activeCount: active, workers: workers, roundInfo: round)
    }
}
