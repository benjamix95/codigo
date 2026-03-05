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
