import Foundation

/// Orchestrator that produces a task plan for the swarm
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

    /// System prompt for the orchestrator
    private static let systemPrompt = """
        You are an orchestrator for a system of specialized agents. Available roles:
        - planner: breaks down the task into clear steps
        - coder: writes or modifies code
        - debugger: identifies and fixes bugs
        - reviewer: reviews code and suggests improvements
        - docWriter: writes documentation
        - securityAuditor: security analysis and vulnerability assessment
        - testWriter: writes tests

        Produce a SINGLE JSON block: an array of tasks. Format: [{"role":"planner","taskDescription":"...","order":1}, ...]
        Use only the roles needed for the request. Order by dependencies (e.g. planner before coder).
        Do not include text outside the JSON. Only the JSON array.
        """

    /// Produces a task plan for the user request
    public func plan(userPrompt: String, context: WorkspaceContext) async throws -> [AgentTask] {
        let enabledRolesList = config.enabledRoles.map { $0.rawValue }.joined(separator: ", ")
        let userMessage = """
            User request: \(userPrompt)
            \(context.contextPrompt())

            Enabled roles: \(enabledRolesList)
            Produce the JSON array of tasks.
            """

        let fullPrompt = "\(Self.systemPrompt)\n\n\(userMessage)"
        let rawOutput = try await collectProviderOutput(
            provider: provider, prompt: fullPrompt, context: context)

        return try parseTasks(from: rawOutput)
    }

    /// Collects full output from an LLMProvider
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
                    taskDescription: "Break down the request into implementable steps and dependencies.",
                    order: 1))
        }
        if config.enabledRoles.contains(.coder) {
            tasks.append(
                AgentTask(
                    role: .coder,
                    taskDescription:
                        "Implement the user request completely and verifiably.",
                    order: tasks.isEmpty ? 1 : 2))
        } else if config.enabledRoles.contains(.debugger) {
            tasks.append(
                AgentTask(
                    role: .debugger,
                    taskDescription:
                        "Analyze and fix the main issues reported in the request.",
                    order: tasks.isEmpty ? 1 : 2))
        }
        return tasks
    }
}
