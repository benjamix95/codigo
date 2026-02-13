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

    public init(
        partitionCount: Int = 3,
        yoloMode: Bool = false,
        enabledPhases: ReviewPhase = .analysisAndExecution
    ) {
        self.partitionCount = min(8, max(2, partitionCount))
        self.yoloMode = yoloMode
        self.enabledPhases = enabledPhases
    }
}
