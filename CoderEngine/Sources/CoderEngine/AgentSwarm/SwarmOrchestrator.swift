import Foundation

/// Orchestratore che produce un piano di task per il swarm
public actor SwarmOrchestrator {
    private let config: SwarmConfig
    private let openAIClient: OpenAICompletionsClient?
    private let codexProvider: CodexCLIProvider?

    public init(
        config: SwarmConfig,
        openAIClient: OpenAICompletionsClient?,
        codexProvider: CodexCLIProvider?
    ) {
        self.config = config
        self.openAIClient = openAIClient
        self.codexProvider = codexProvider
    }

    /// Prompt di sistema per l'orchestratore
    private static let systemPrompt = """
    Sei un orchestratore per un sistema di agenti specializzati. Ruoli disponibili:
    - planner: scompone il compito in passi chiari
    - coder: scrive o modifica codice
    - debugger: identifica e risolve bug
    - reviewer: revisiona codice e suggerisce miglioramenti
    - docWriter: scrive documentazione
    - securityAuditor: analisi sicurezza e vulnerabilità
    - testWriter: scrive test

    Produci UN SOLO blocco JSON: un array di task. Formato: [{"role":"planner","taskDescription":"...","order":1}, ...]
    Usa solo i ruoli necessari per la richiesta. Ordina per dipendenze (es. planner prima di coder).
    Non includere testo fuori dal JSON. Solo l'array JSON.
    """

    /// Produce un piano di task per la richiesta dell'utente
    public func plan(userPrompt: String, context: WorkspaceContext) async throws -> [AgentTask] {
        let enabledRolesList = config.enabledRoles.map { $0.rawValue }.joined(separator: ", ")
        let userMessage = """
        Richiesta utente: \(userPrompt)
        \(context.contextPrompt())

        Ruoli abilitati: \(enabledRolesList)
        Produci l'array JSON di task.
        """

        let rawOutput: String
        switch config.orchestratorBackend {
        case .openai:
            guard let client = openAIClient else {
                throw CoderEngineError.apiError("OpenAI client non configurato per orchestratore")
            }
            rawOutput = try await client.complete(messages: [
                .system(Self.systemPrompt),
                .user(userMessage)
            ])
        case .codex:
            guard let provider = codexProvider else {
                throw CoderEngineError.apiError("Codex provider non configurato per orchestratore")
            }
            let fullPrompt = "\(Self.systemPrompt)\n\n\(userMessage)"
            rawOutput = try await collectCodexOutput(provider: provider, prompt: fullPrompt, context: context)
        }

        return try parseTasks(from: rawOutput)
    }

    /// Raccolta output completo da Codex
    private func collectCodexOutput(provider: CodexCLIProvider, prompt: String, context: WorkspaceContext) async throws -> String {
        let stream = try await provider.send(prompt: prompt, context: context)
        var full = ""
        for try await event in stream {
            if case .textDelta(let delta) = event {
                full += delta
            }
        }
        return full
    }

    /// Estrae e parsa l'array JSON dal testo (gestisce markdown code blocks)
    private func parseTasks(from raw: String) throws -> [AgentTask] {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Estrai da ```json ... ``` se presente
        if let start = trimmed.range(of: "```json"),
           let end = trimmed.range(of: "```", range: start.upperBound..<trimmed.endIndex) {
            trimmed = String(trimmed[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let start = trimmed.range(of: "```"),
                  let end = trimmed.range(of: "```", range: start.upperBound..<trimmed.endIndex) {
            trimmed = String(trimmed[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = trimmed.data(using: .utf8) else {
            throw CoderEngineError.apiError("Orchestrator: output non valido")
        }

        struct RawTask: Codable {
            let role: String
            let taskDescription: String
            let order: Int
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rawTasks: [RawTask]
        do {
            rawTasks = try decoder.decode([RawTask].self, from: data)
        } catch {
            throw CoderEngineError.apiError("Orchestrator: JSON non valido - \(error.localizedDescription)")
        }

        return rawTasks.compactMap { raw -> AgentTask? in
            guard let role = AgentRole(rawValue: raw.role),
                  config.enabledRoles.contains(role) else { return nil }
            return AgentTask(role: role, taskDescription: raw.taskDescription, order: raw.order)
        }.sorted { $0.order < $1.order }
    }
}
