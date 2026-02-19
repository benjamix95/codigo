import Foundation

/// Tools ridotti per planning: solo lettura codebase (Read, Glob, Grep)
private let planModeClaudeTools = ["Read", "Glob", "Grep"]

/// Provider che esegue la fase planning: analizza il codebase e propone opzioni numerate.
/// Usa provider con restrizioni: Codex read-only, Claude solo Read/Glob/Grep.
/// La fase execute viene delegata a Codex/Claude dalla ChatPanelView.
public final class PlanModeProvider: LLMProvider, @unchecked Sendable {
    public let id = "plan-mode"
    public let displayName = "Plan"

    private let codexProvider: CodexCLIProvider?
    private let claudeProvider: ClaudeCLIProvider?
    private let codexParams: CodexCreateParams?
    private let backend: String
    private let claudePath: String?
    private let claudeModel: String?
    private let executionController: ExecutionController?

    private static let planningPromptPrefix = """
    Sei in modalità planning. Analizza il codebase e il contesto forniti, poi proponi un piano di implementazione.

    Regole:
    - Proponi da 2 a 4 opzioni numerate (Opzione 1, Opzione 2, ...)
    - Per ogni opzione: approccio, pro/contro, stima complessità, file principali coinvolti
    - Usa il formato: "## Opzione N: [Titolo]\n[Descrizione dettagliata]\n- Pro: ...\n- Contro: ...\n- Complessità: ...\n- File: ..."
    - Non eseguire modifiche, solo proporre il piano

    Richiesta dell'utente:

    """

    public init(
        codexProvider: CodexCLIProvider?,
        claudeProvider: ClaudeCLIProvider?,
        codexParams: CodexCreateParams? = nil,
        backend: String = "codex",
        claudePath: String? = nil,
        claudeModel: String? = nil,
        executionController: ExecutionController? = nil
    ) {
        self.codexProvider = codexProvider
        self.claudeProvider = claudeProvider
        self.codexParams = codexParams
        self.backend = backend
        self.claudePath = claudePath
        self.claudeModel = claudeModel
        self.executionController = executionController
    }

    private var activeProvider: (any LLMProvider)? {
        if backend == "claude", let _ = claudeProvider { return claudeProvider }
        return codexProvider
    }

    public func isAuthenticated() -> Bool {
        activeProvider?.isAuthenticated() ?? false
    }

    /// Crea provider con restrizioni per planning: Codex read-only, Claude solo Read/Glob/Grep.
    private func planningProvider() -> (any LLMProvider)? {
        if backend == "codex", let cp = codexParams {
            return CodexCLIProvider(
                codexPath: cp.codexPath,
                sandboxMode: .readOnly,
                modelOverride: cp.modelOverride,
                modelReasoningEffort: cp.modelReasoningEffort,
                askForApproval: cp.askForApproval,
                executionController: executionController,
                executionScope: .plan
            )
        }
        if backend == "claude" {
            let path = claudePath?.isEmpty == false ? claudePath : nil
            let model = claudeModel?.trimmingCharacters(in: .whitespaces).isEmpty == false ? claudeModel : nil
            return ClaudeCLIProvider(
                claudePath: path,
                model: model,
                allowedTools: planModeClaudeTools,
                executionController: executionController,
                executionScope: .plan
            )
        }
        return nil
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        guard let provider = planningProvider() else {
            throw CoderEngineError.cliNotFound("Plan mode richiede Codex o Claude CLI")
        }
        let planningPrompt = Self.planningPromptPrefix + prompt
        return try await provider.send(prompt: planningPrompt, context: context, imageURLs: imageURLs)
    }
}
