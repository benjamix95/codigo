import Foundation

enum CodeReviewTab: String, CaseIterable {
    case commands = "Commands"
    case findings = "Findings"
    case timeline = "Timeline"
    case config = "Config"
}

struct ReviewWorkerRow: Identifiable {
    let id: String
    let description: String
    let severity: String
    let fileCount: Int
    let files: [String]
    let filesSummary: String
}

struct CodeReviewMetrics {
    let cards: [SwarmLiveCardState]
    let activeCount: Int
    let workers: [ReviewWorkerRow]
    let roundInfo: (round: String, maxRounds: String)?
}

func shouldDisplayCodeReviewMetrics(coderMode: CoderMode, hasReviewArtifacts: Bool) -> Bool {
    coderMode == .codeReviewMultiSwarm || hasReviewArtifacts
}

func hasCodeReviewArtifacts(
    cards: [SwarmLiveCardState],
    workerActivities: [TaskActivity],
    activities: [TaskActivity]
) -> Bool {
    !cards.isEmpty
        || !workerActivities.isEmpty
        || activities.contains(where: { $0.type == "review-fix-round" })
}
