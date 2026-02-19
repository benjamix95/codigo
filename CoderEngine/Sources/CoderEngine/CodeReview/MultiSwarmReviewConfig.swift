import Foundation

/// Fasi abilitate per il multi-swarm review
public enum ReviewPhase: String, Sendable {
    case analysisOnly = "analysis-only"
    case analysisAndExecution = "analysis-and-execution"
}

/// Configurazione per Multi-Swarm Code Review
public struct MultiSwarmReviewConfig: Sendable {
    public let partitionCount: Int
    public let yoloMode: Bool
    public let enabledPhases: ReviewPhase
    public let maxReviewRounds: Int
    /// Backend per Fase 1 (analisi): "codex" o "claude"
    public let analysisBackend: String

    public init(
        partitionCount: Int = 3,
        yoloMode: Bool = false,
        enabledPhases: ReviewPhase = .analysisAndExecution,
        maxReviewRounds: Int = 3,
        analysisBackend: String = "codex"
    ) {
        self.partitionCount = min(12, max(2, partitionCount))
        self.yoloMode = yoloMode
        self.enabledPhases = enabledPhases
        self.maxReviewRounds = min(10, max(1, maxReviewRounds))
        self.analysisBackend = (analysisBackend == "claude") ? "claude" : "codex"
    }
}
