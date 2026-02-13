import Foundation

private let planModeBackendKey = "plan_mode_backend"

/// Provider che esegue la fase planning: analizza il codebase e propone opzioni numerate.
/// La fase execute viene delegata a Codex/Claude dalla ChatPanelView.
/// Il backend (codex | claude) è letto da plan_mode_backend in UserDefaults.
public final class PlanModeProvider: LLMProvider, @unchecked Sendable {
    public let id = "plan-mode"
    public let displayName = "Plan"

    private let codexProvider: CodexCLIProvider?
    private let claudeProvider: ClaudeCLIProvider?

    private static let planningPromptPrefix = """
    Sei in modalità planning. Analizza il codebase e il contesto forniti, poi proponi un piano di implementazione.

    Regole:
    - Proponi da 2 a 4 opzioni numerate (Opzione 1, Opzione 2, ...)
    - Per ogni opzione: approccio, pro/contro, stima complessità, file principali coinvolti
    - Usa il formato: "## Opzione N: [Titolo]\n[Descrizione dettagliata]\n- Pro: ...\n- Contro: ...\n- Complessità: ...\n- File: ..."
    - Non eseguire modifiche, solo proporre il piano

    Richiesta dell'utente:

    """

    public init(codexProvider: CodexCLIProvider?, claudeProvider: ClaudeCLIProvider?) {
        self.codexProvider = codexProvider
        self.claudeProvider = claudeProvider
    }

    private var activeProvider: (any LLMProvider)? {
        let backend = UserDefaults.standard.string(forKey: planModeBackendKey) ?? "codex"
        if backend == "claude", let claude = claudeProvider {
            return claude
        }
        return codexProvider
    }

    public func isAuthenticated() -> Bool {
        activeProvider?.isAuthenticated() ?? false
    }

    public func send(prompt: String, context: WorkspaceContext) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        guard let provider = activeProvider else {
            throw CoderEngineError.cliNotFound("Plan mode richiede Codex o Claude CLI")
        }
        let planningPrompt = Self.planningPromptPrefix + prompt
        return try await provider.send(prompt: planningPrompt, context: context)
    }
}
