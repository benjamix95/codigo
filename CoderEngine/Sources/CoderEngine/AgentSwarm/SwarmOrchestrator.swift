import Foundation

/// Orchestratore che produce un piano di task per il swarm
public actor SwarmOrchestrator {
    private let config: SwarmConfig
    private let provider: any LLMProvider

    public init(
        config: SwarmConfig,
        provider: any LLMProvider
    ) {
        self.config = config
        self.provider = provider
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

        let fullPrompt = "\(Self.systemPrompt)\n\n\(userMessage)"
        let rawOutput = try await collectProviderOutput(
            provider: provider, prompt: fullPrompt, context: context)

        return try parseTasks(from: rawOutput)
    }

    /// Raccolta output completo da un LLMProvider
    private func collectProviderOutput(
        provider: any LLMProvider, prompt: String, context: WorkspaceContext
    ) async throws -> String {
        let stream = try await provider.send(prompt: prompt, context: context, imageURLs: nil)
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
            let end = trimmed.range(of: "```", range: start.upperBound..<trimmed.endIndex)
        {
            trimmed = String(trimmed[start.upperBound..<end.lowerBound]).trimmingCharacters(
                in: .whitespacesAndNewlines)
        } else if let start = trimmed.range(of: "```"),
            let end = trimmed.range(of: "```", range: start.upperBound..<trimmed.endIndex)
        {
            trimmed = String(trimmed[start.upperBound..<end.lowerBound]).trimmingCharacters(
                in: .whitespacesAndNewlines)
        }

        guard !trimmed.isEmpty else {
            return fallbackTasks()
        }

        struct RawTask: Codable {
            let role: String
            let taskDescription: String
            let order: Int
        }

        func decodeTasks(from text: String) -> [RawTask]? {
            guard let data = text.data(using: .utf8) else { return nil }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try? decoder.decode([RawTask].self, from: data)
        }

        let rawTasks: [RawTask]
        if let parsed = decodeTasks(from: trimmed) {
            rawTasks = parsed
        } else if let start = trimmed.firstIndex(of: "["),
            let end = trimmed.lastIndex(of: "]"),
            start < end
        {
            let candidate = String(trimmed[start...end])
            if let parsed = decodeTasks(from: candidate) {
                rawTasks = parsed
            } else {
                return fallbackTasks()
            }
        } else {
            return fallbackTasks()
        }

        let mapped = rawTasks.compactMap { raw -> AgentTask? in
            guard let role = AgentRole(rawValue: raw.role),
                config.enabledRoles.contains(role)
            else { return nil }
            return AgentTask(role: role, taskDescription: raw.taskDescription, order: raw.order)
        }.sorted { $0.order < $1.order }
        return mapped.isEmpty ? fallbackTasks() : mapped
    }

    private func fallbackTasks() -> [AgentTask] {
        var tasks: [AgentTask] = []
        if config.enabledRoles.contains(.planner) {
            tasks.append(
                AgentTask(
                    role: .planner,
                    taskDescription: "Scomponi la richiesta in passi implementabili e dipendenze.",
                    order: 1))
        }
        if config.enabledRoles.contains(.coder) {
            tasks.append(
                AgentTask(
                    role: .coder,
                    taskDescription:
                        "Implementa la richiesta utente in modo completo e verificabile.",
                    order: tasks.isEmpty ? 1 : 2))
        } else if config.enabledRoles.contains(.debugger) {
            tasks.append(
                AgentTask(
                    role: .debugger,
                    taskDescription:
                        "Analizza e correggi i problemi principali segnalati dalla richiesta.",
                    order: tasks.isEmpty ? 1 : 2))
        }
        return tasks
    }
}
