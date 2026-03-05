import Foundation
import CoderEngine

extension TaskActivityStore {
    // MARK: - Code Review Session Integration

    /// Ingests a CodeReviewSessionSnapshot and publishes relevant activities
    /// for LiveCard display. Called from the `CodeReviewSessionState.onStateChange` callback.
    func ingestCodeReviewSnapshot(_ snapshot: CodeReviewSessionSnapshot) {
        let activity = TaskActivity(
            type: "code_review_update",
            title: codeReviewTitle(for: snapshot.phase),
            detail: snapshot.statusSummary,
            payload: codeReviewPayload(snapshot),
            phase: codeReviewActivityPhase(snapshot.phase),
            isRunning: snapshot.phase.isActive,
            groupId: "code-review"
        )
        addActivity(activity)
    }

    /// Ingests a single code review event as a TaskActivity.
    func ingestCodeReviewEvent(_ event: CodeReviewSessionEvent) {
        let activity = TaskActivity(
            type: "code_review_event",
            title: codeReviewEventTitle(event.type),
            detail: event.detail,
            payload: event.toPayload(),
            phase: .executing,
            isRunning: false,
            groupId: "code-review"
        )
        addActivity(activity)
    }

    // MARK: - Helpers

    private func codeReviewTitle(for phase: ReviewSessionPhase) -> String {
        switch phase {
        case .idle: return "Code Review Idle"
        case .analyzing: return "Analyzing Code..."
        case .fixing: return "Applying Fixes..."
        case .testing: return "Running Tests..."
        case .reReviewing: return "Re-Reviewing..."
        case .completed: return "Code Review Completed"
        case .failed: return "Code Review Failed"
        }
    }

    private func codeReviewActivityPhase(
        _ phase: ReviewSessionPhase
    ) -> ActivityPhase {
        switch phase {
        case .idle: return .thinking
        case .analyzing: return .searching
        case .fixing: return .editing
        case .testing: return .executing
        case .reReviewing: return .searching
        case .completed: return .thinking
        case .failed: return .thinking
        }
    }

    private func codeReviewPayload(
        _ snapshot: CodeReviewSessionSnapshot
    ) -> [String: String] {
        var payload: [String: String] = [
            "phase": snapshot.phase.rawValue,
            "findings_count": String(snapshot.findings.count),
            "open_count": String(snapshot.openFindings.count),
            "round": String(snapshot.currentRound),
            "active_workers": String(snapshot.activeWorkerCount),
        ]
        if let scope = snapshot.scope {
            payload["scope"] = scope.type.rawValue
            payload["scope_files"] = String(scope.files.count)
        }
        if let error = snapshot.lastError {
            payload["error"] = error
        }
        return payload
    }

    private func codeReviewEventTitle(
        _ type: CodeReviewSessionEvent.EventType
    ) -> String {
        switch type {
        case .sessionStarted: return "Review Started"
        case .sessionCompleted: return "Review Completed"
        case .analysisStarted: return "Analysis Started"
        case .analysisCompleted: return "Analysis Completed"
        case .findingAdded: return "Finding Added"
        case .findingFixApplied: return "Fix Applied"
        case .findingDismissed: return "Finding Dismissed"
        case .findingCommented: return "Comment Added"
        case .roundStarted: return "Round Started"
        case .roundCompleted: return "Round Completed"
        case .workerSpawned: return "Worker Spawned"
        case .workerCompleted: return "Worker Completed"
        case .testsPassed: return "Tests Passed"
        case .testsFailed: return "Tests Failed"
        case .configUpdated: return "Config Updated"
        case .error: return "Error"
        }
    }
}

// MARK: - ReviewSessionPhase Helpers

extension ReviewSessionPhase {
    var isActive: Bool {
        switch self {
        case .analyzing, .fixing, .testing, .reReviewing:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }
}
