import Foundation
import os.log

/// Enabled phases for multi-swarm review (legacy — renamed to avoid collision with Pipeline ReviewPhase)
public enum ReviewEnabledPhase: String, Sendable {
    case analysisOnly = "analysis-only"
    case analysisAndExecution = "analysis-and-execution"
}

/// Configuration for Multi-Swarm Code Review
public struct MultiSwarmReviewConfig: Sendable {
    /// Maximum number of concurrent review/fix workers (dynamic count, capped here).
    /// Clamped to 1...12.
    public let maxWorkers: Int
    public let enabledPhases: ReviewEnabledPhase
    /// Maximum review-fix rounds. Clamped to 1...10.
    public let maxReviewRounds: Int
    /// Backend for Phase 1 (analysis)
    public let analysisBackend: String
    /// Backend for Phase 2 (fix execution)
    public let executionBackend: String

    public init(
        maxWorkers: Int = 6,
        enabledPhases: ReviewEnabledPhase = .analysisAndExecution,
        maxReviewRounds: Int = 3,
        analysisBackend: String = "codex",
        executionBackend: String = "codex"
    ) {
        let clampedWorkers = min(12, max(1, maxWorkers))
        let clampedRounds = min(10, max(1, maxReviewRounds))
        if clampedWorkers != maxWorkers {
            Logger(subsystem: "com.codigo.codeReview", category: "config")
                .info("maxWorkers clamped from \(maxWorkers) to \(clampedWorkers)")
        }
        if clampedRounds != maxReviewRounds {
            Logger(subsystem: "com.codigo.codeReview", category: "config")
                .info("maxReviewRounds clamped from \(maxReviewRounds) to \(clampedRounds)")
        }
        self.maxWorkers = clampedWorkers
        self.enabledPhases = enabledPhases
        self.maxReviewRounds = clampedRounds
        self.analysisBackend = analysisBackend.isEmpty ? "codex" : analysisBackend
        self.executionBackend = executionBackend.isEmpty ? "codex" : executionBackend
    }
}
