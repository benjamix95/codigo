import Foundation

/// Enabled phases for multi-swarm review
public enum ReviewPhase: String, Sendable {
    case analysisOnly = "analysis-only"
    case analysisAndExecution = "analysis-and-execution"
}

/// Backend for Phase 2 (fix execution): supports CLI and API
public enum CodeReviewExecutionBackend: String, Sendable, CaseIterable {
    case codex
    case claude
    case anthropicApi = "anthropic-api"
    case openaiApi = "openai-api"
    case googleApi = "google-api"
    case openrouterApi = "openrouter-api"

    public var displayName: String {
        switch self {
        case .codex: return "Codex CLI"
        case .claude: return "Claude CLI"
        case .anthropicApi: return "Anthropic API"
        case .openaiApi: return "OpenAI API"
        case .googleApi: return "Google API"
        case .openrouterApi: return "OpenRouter API"
        }
    }
}

/// Configuration for Multi-Swarm Code Review
public struct MultiSwarmReviewConfig: Sendable {
    /// Maximum number of concurrent review/fix workers (dynamic count, capped here)
    public let maxWorkers: Int
    public let yoloMode: Bool
    public let enabledPhases: ReviewPhase
    public let maxReviewRounds: Int
    /// Backend for Phase 1 (analysis)
    public let analysisBackend: String
    /// Backend for Phase 2 (fix execution)
    public let executionBackend: String

    public init(
        maxWorkers: Int = 6,
        yoloMode: Bool = false,
        enabledPhases: ReviewPhase = .analysisAndExecution,
        maxReviewRounds: Int = 3,
        analysisBackend: String = "codex",
        executionBackend: String = "codex"
    ) {
        self.maxWorkers = min(12, max(1, maxWorkers))
        self.yoloMode = yoloMode
        self.enabledPhases = enabledPhases
        self.maxReviewRounds = min(10, max(1, maxReviewRounds))
        self.analysisBackend = analysisBackend
        self.executionBackend = executionBackend
    }
}
