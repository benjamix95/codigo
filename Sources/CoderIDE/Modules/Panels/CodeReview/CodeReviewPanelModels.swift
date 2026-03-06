import CoderEngine
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
    let severity: FindingSeverity
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

enum CodeReviewPanelAction {
    case quickCommand(id: String)
    case againstCommit(ref: String, autofixEnabled: Bool, maxRounds: Int)
    case rerunSession(sessionId: String)
    case applyFix(sessionId: String, findingId: String)
    case dismissFinding(sessionId: String, findingId: String, reason: String)
    case applyAllFixes(sessionId: String, findingIds: [String])
    case dismissAll(sessionId: String, findingIds: [String], reason: String)
    case exportSummary(sessionId: String)
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
