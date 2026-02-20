import Foundation

/// Orchestratore che produce un piano di task per il swarm
public actor SwarmOrchestrator {
    private let config: SwarmConfig
    private let openAIClient: OpenAICompletionsClient?
    private let codexProvider: CodexCLIProvider?
    private let claudeProvider: ClaudeCLIProvider?
    private let geminiProvider: GeminiCLIProvider?

    public init(
        config: SwarmConfig,
        openAIClient: OpenAICompletionsClient?,
        codexProvider: CodexCLIProvider?,
        claudeProvider: ClaudeCLIProvider? = nil,
        geminiProvider: GeminiCLIProvider? = nil
    ) {
        self.config = config
        self.openAIClient = openAIClient
        self.codexProvider = codexProvider
        self.claudeProvider = claudeProvider
        self.geminiProvider = geminiProvider
    }

    /// System prompt for the orchestrator – language-neutral, concise, structured.
    private static let systemPrompt = """
        You are an orchestrator for a multi-agent coding system. Available specialist roles:
        - planner: breaks down the task into clear implementation steps (no code)
        - coder: writes or modifies code according to the plan
        - debugger: identifies bugs, analyzes stack traces, fixes issues
        - reviewer: reviews code for style, best practices, suggests optimizations
        - docWriter: writes documentation (README, comments, docstrings)
        - securityAuditor: analyzes code for vulnerabilities and insecure dependencies
        - testWriter: writes unit, integration, and smoke tests

        Produce EXACTLY ONE JSON block: an array of task objects.
        Format: [{"role":"<role>","taskDescription":"<description>","order":<int>}]

        Rules:
        1. Use only the roles that are strictly necessary for the request.
        2. Order tasks by dependency (e.g. planner before coder, coder before testWriter).
        3. Tasks with the same "order" value run in parallel.
        4. Output ONLY the JSON array – no commentary, no markdown fences, no extra text.
        """

    /// Produce un piano di task per la richiesta dell'utente
    public func plan(userPrompt: String, context: WorkspaceContext) async throws -> [AgentTask] {
        let enabledRolesList = config.enabledRoles.map { $0.rawValue }.joined(separator: ", ")
        let userMessage = """
            User request: \(userPrompt)
            \(context.contextPrompt())

            Enabled roles: \(enabledRolesList)
            Produce the JSON array of tasks.
            """

        let rawOutput: String
        switch config.orchestratorBackend {
        case .openai:
            guard let client = openAIClient else {
                throw CoderEngineError.apiError("OpenAI client not configured for orchestrator")
            }
            rawOutput = try await client.complete(messages: [
                .system(Self.systemPrompt),
                .user(userMessage),
            ])
        case .codex:
            guard let provider = codexProvider else {
                throw CoderEngineError.apiError("Codex provider not configured for orchestrator")
            }
            let fullPrompt = "\(Self.systemPrompt)\n\n\(userMessage)"
            rawOutput = try await collectProviderOutput(
                provider: provider, prompt: fullPrompt, context: context)
        case .claude:
            guard let provider = claudeProvider else {
                throw CoderEngineError.apiError("Claude provider not configured for orchestrator")
            }
            let fullPrompt = "\(Self.systemPrompt)\n\n\(userMessage)"
            rawOutput = try await collectProviderOutput(
                provider: provider, prompt: fullPrompt, context: context)
        case .gemini:
            guard let provider = geminiProvider else {
                throw CoderEngineError.apiError(
                    "Gemini CLI provider not configured for orchestrator")
            }
            let fullPrompt = "\(Self.systemPrompt)\n\n\(userMessage)"
            rawOutput = try await collectProviderOutput(
                provider: provider, prompt: fullPrompt, context: context)
        }

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

        // Extract from ```json ... ``` if present
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
                    taskDescription:
                        "Break down the request into clear, implementable steps and identify dependencies.",
                    order: 1))
        }
        if config.enabledRoles.contains(.coder) {
            tasks.append(
                AgentTask(
                    role: .coder,
                    taskDescription: "Implement the user request completely and verifiably.",
                    order: tasks.isEmpty ? 1 : 2))
        } else if config.enabledRoles.contains(.debugger) {
            tasks.append(
                AgentTask(
                    role: .debugger,
                    taskDescription: "Analyze and fix the main issues described in the request.",
                    order: tasks.isEmpty ? 1 : 2))
        }
        return tasks
    }
}
