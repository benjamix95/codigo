import Foundation

/// Backend dell'orchestratore
public enum OrchestratorBackend: String, CaseIterable, Codable, Sendable {
    case openai
    case codex
    case claude
    case anthropicAPI = "anthropic-api"
    case googleAPI = "google-api"
    case openrouterAPI = "openrouter-api"
    case gemini
    case minimaxAPI = "minimax-api"
}

/// Backend dei worker
public enum WorkerBackend: String, CaseIterable, Codable, Sendable {
    case codex
    case claude
    case gemini
    case openaiAPI = "openai-api"
    case anthropicAPI = "anthropic-api"
    case googleAPI = "google-api"
    case openrouterAPI = "openrouter-api"
    case minimaxAPI = "minimax-api"
}

/// Configurazione del swarm di agenti
public struct SwarmConfig: Sendable {
    public let orchestratorBackend: OrchestratorBackend
    public let workerBackend: WorkerBackend
    public let enabledRoles: Set<AgentRole>
    public let maxRounds: Int
    public let autoPostCodePipeline: Bool
    public let maxPostCodeRetries: Int
    public let maxReviewLoops: Int

    public init(
        orchestratorBackend: OrchestratorBackend = .openai,
        workerBackend: WorkerBackend = .codex,
        enabledRoles: Set<AgentRole>? = nil,
        maxRounds: Int = 1,
        autoPostCodePipeline: Bool = true,
        maxPostCodeRetries: Int = 10,
        maxReviewLoops: Int = 2
    ) {
        self.orchestratorBackend = orchestratorBackend
        self.workerBackend = workerBackend
        self.enabledRoles = enabledRoles ?? Set(AgentRole.allCases)
        self.maxRounds = maxRounds
        self.autoPostCodePipeline = autoPostCodePipeline
        self.maxPostCodeRetries = maxPostCodeRetries
        self.maxReviewLoops = min(5, max(0, maxReviewLoops))
    }
}
