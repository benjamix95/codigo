import CoderEngine
import Foundation

extension CodeReviewPanelView {
    func metrics() -> CodeReviewMetrics {
        let selectedSessionId = taskActivityStore.selectedCodeReviewSessionId(for: conversationId)
        let conversationActivities = scopedTaskActivitiesForConversation(
            taskActivityStore.activities,
            conversationId: conversationId
        )
        let activities = scopedReviewActivitiesForSession(
            conversationActivities,
            sessionId: selectedSessionId
        )
        let cards = taskActivityStore
            .swarmCardStates(for: conversationId)
            .filter {
                isCodeReviewSwarmCard($0)
                    && reviewCardBelongsToConversation($0, conversationId: conversationId)
                    && reviewCardBelongsToSession($0, sessionId: selectedSessionId)
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
            let resolvedSeverity = FindingSeverity(rawValue: sev.lowercased()) ?? .warning
            return ReviewWorkerRow(
                id: wid,
                description: desc,
                severity: resolvedSeverity,
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
