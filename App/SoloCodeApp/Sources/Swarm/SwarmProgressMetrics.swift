import Foundation

struct SwarmProgressMetrics {
    let totalSteps: Int
    let completedSteps: Int
    let failedSteps: Int
    let runningSteps: Int
    let pendingSteps: Int
    /// True when pipeline has a single internal task (explorer/todo) — step count should be hidden.
    let isInternalSingleTaskPhase: Bool

    init(steps: [SwarmStep], pipelineSnapshot: PipelineConversationSnapshot?) {
        let stepCompleted = steps.filter { $0.status == .completed }.count
        let stepFailed = steps.filter { $0.status == .failed }.count
        let stepRunning = steps.filter { $0.status == .inProgress }.count
        let snapshotCompleted = max(0, pipelineSnapshot?.completedTasks ?? 0)
        let snapshotTotal = max(0, pipelineSnapshot?.totalTasks ?? 0)

        totalSteps = max(steps.count, snapshotTotal)
        completedSteps = min(totalSteps, max(stepCompleted, snapshotCompleted))
        failedSteps = stepFailed

        let inferredRunning: Int
        if stepRunning > 0 {
            inferredRunning = stepRunning
        } else if pipelineSnapshot?.isRunning == true, completedSteps + failedSteps < totalSteps {
            inferredRunning = totalSteps > 0 ? 1 : 0
        } else {
            inferredRunning = 0
        }

        runningSteps = min(max(totalSteps - completedSteps - failedSteps, 0), inferredRunning)
        pendingSteps = max(totalSteps - completedSteps - runningSteps - failedSteps, 0)
        isInternalSingleTaskPhase = steps.isEmpty && snapshotTotal == 1 && (pipelineSnapshot?.isRunning == true)
    }

    var progressedSteps: Int {
        min(totalSteps, completedSteps + runningSteps + failedSteps)
    }

    var progressFraction: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(progressedSteps) / Double(totalSteps)
    }

    var progressLabel: String {
        if isInternalSingleTaskPhase { return "Running…" }
        let noun = totalSteps == 1 ? "step" : "steps"
        return "\(progressedSteps)/\(max(totalSteps, 1)) \(noun)"
    }

    var summaryLabel: String? {
        guard totalSteps > 0 else { return nil }

        var parts: [String] = []
        if completedSteps > 0 {
            parts.append("\(completedSteps) done")
        }
        if runningSteps > 0 {
            parts.append("\(runningSteps) running")
        }
        if failedSteps > 0 {
            parts.append("\(failedSteps) failed")
        }
        if pendingSteps > 0 {
            parts.append("\(pendingSteps) pending")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}
