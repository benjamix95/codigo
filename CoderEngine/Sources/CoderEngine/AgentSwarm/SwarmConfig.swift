import Foundation

/// Backend dell'orchestratore: OpenAI (leggero) o Codex (pesante)
public enum OrchestratorBackend: String, CaseIterable, Codable, Sendable {
    case openai
    case codex
}

/// Configurazione del swarm di agenti
public struct SwarmConfig: Sendable {
    /// Provider dell'orchestratore
    public let orchestratorBackend: OrchestratorBackend

    /// Ruoli attivi (default: tutti)
    public let enabledRoles: Set<AgentRole>

    /// Massimo numero di round (iterazioni supervisor), default 1
    public let maxRounds: Int

    /// Se true, dopo Coder vengono aggiunti automaticamente Reviewer e TestWriter
    public let autoPostCodePipeline: Bool

    /// Ripete Debugger + test finché non passano (test OK, no errori, no warning)
    public let maxPostCodeRetries: Int

    public init(
        orchestratorBackend: OrchestratorBackend = .openai,
        enabledRoles: Set<AgentRole>? = nil,
        maxRounds: Int = 1,
        autoPostCodePipeline: Bool = true,
        maxPostCodeRetries: Int = 10
    ) {
        self.orchestratorBackend = orchestratorBackend
        self.enabledRoles = enabledRoles ?? Set(AgentRole.allCases)
        self.maxRounds = maxRounds
        self.autoPostCodePipeline = autoPostCodePipeline
        self.maxPostCodeRetries = maxPostCodeRetries
    }
}
