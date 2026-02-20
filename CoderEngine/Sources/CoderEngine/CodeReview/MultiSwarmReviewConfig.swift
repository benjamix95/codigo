import Foundation

/// Fasi abilitate per il multi-swarm review
public enum ReviewPhase: String, Sendable {
    case analysisOnly = "analysis-only"
    case analysisAndExecution = "analysis-and-execution"
}

/// Backend per Fase 2 (esecuzione correzioni): supporta CLI e API
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

/// Configurazione per Multi-Swarm Code Review
public struct MultiSwarmReviewConfig: Sendable {
    public let partitionCount: Int
    public let yoloMode: Bool
    public let enabledPhases: ReviewPhase
    public let maxReviewRounds: Int
    /// Backend per Fase 1 (analisi): "codex" o "claude"
    public let analysisBackend: String
    /// Backend per Fase 2 (esecuzione correzioni): codex, claude, anthropic-api, openai-api, google-api, openrouter-api
    public let executionBackend: String

    public init(
        partitionCount: Int = 3,
        yoloMode: Bool = false,
        enabledPhases: ReviewPhase = .analysisAndExecution,
        maxReviewRounds: Int = 3,
        analysisBackend: String = "codex",
        executionBackend: String = "codex"
    ) {
        self.partitionCount = min(12, max(2, partitionCount))
        self.yoloMode = yoloMode
        self.enabledPhases = enabledPhases
        self.maxReviewRounds = min(10, max(1, maxReviewRounds))
        self.analysisBackend = (analysisBackend == "claude") ? "claude" : "codex"
        self.executionBackend = executionBackend
    }
}
