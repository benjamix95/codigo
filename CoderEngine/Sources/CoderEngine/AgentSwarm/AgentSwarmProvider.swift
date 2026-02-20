import Foundation

/// Provider LLM che coordina un swarm di agenti specializzati tramite orchestratore.
/// Supporta Codex CLI, Claude Code CLI e Gemini CLI come worker e orchestratori.
public final class AgentSwarmProvider: LLMProvider, @unchecked Sendable {
    public let id = "agent-swarm"
    public let displayName = "Agent Swarm"

    private let config: SwarmConfig
    private let openAIClient: OpenAICompletionsClient?
    private let codexProvider: CodexCLIProvider
    private let claudeProvider: ClaudeCLIProvider?
    private let geminiProvider: GeminiCLIProvider?
    private let executionController: ExecutionController?

    public init(
        config: SwarmConfig,
        openAIClient: OpenAICompletionsClient?,
        codexProvider: CodexCLIProvider,
        claudeProvider: ClaudeCLIProvider? = nil,
        geminiProvider: GeminiCLIProvider? = nil,
        executionController: ExecutionController? = nil
    ) {
        self.config = config
        self.openAIClient = openAIClient
        self.codexProvider = codexProvider
        self.claudeProvider = claudeProvider
        self.geminiProvider = geminiProvider
        self.executionController = executionController
    }

    public func isAuthenticated() -> Bool {
        // At least the default worker backend must be authenticated
        let defaultWorkerOk = isWorkerAuthenticated(config.workerBackend)
        guard defaultWorkerOk else { return false }

        // Check orchestrator backend
        switch config.orchestratorBackend {
        case .openai: return openAIClient != nil
        case .codex: return codexProvider.isAuthenticated()
        case .claude: return claudeProvider?.isAuthenticated() ?? false
        case .gemini: return geminiProvider?.isAuthenticated() ?? false
        }
    }

    /// Checks if a specific worker backend is authenticated and available.
    private func isWorkerAuthenticated(_ backend: WorkerBackend) -> Bool {
        switch backend {
        case .codex: return codexProvider.isAuthenticated()
        case .claude: return claudeProvider?.isAuthenticated() ?? false
        case .gemini: return geminiProvider?.isAuthenticated() ?? false
        }
    }

    /// Resolves the LLMProvider to use for a given agent role,
    /// respecting per-role overrides and falling back to the default worker backend.
    private func workerProvider(for role: AgentRole) -> any LLMProvider {
        let effectiveBackend = config.effectiveWorkerBackend(for: role)
        return providerForBackend(effectiveBackend)
    }

    /// Returns the default worker provider (used when no role-specific resolution is needed).
    private var defaultWorkerProvider: any LLMProvider {
        providerForBackend(config.workerBackend)
    }

    /// Maps a WorkerBackend to its concrete LLMProvider, with fallback to codex.
    private func providerForBackend(_ backend: WorkerBackend) -> any LLMProvider {
        switch backend {
        case .claude:
            if let claude = claudeProvider, claude.isAuthenticated() { return claude }
            return codexProvider
        case .gemini:
            if let gemini = geminiProvider, gemini.isAuthenticated() { return gemini }
            return codexProvider
        case .codex:
            return codexProvider
        }
    }

    public func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]? = nil
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        var userPrompt = prompt
        if let urls = imageURLs, !urls.isEmpty {
            let refs = urls.map { "[Image: \($0.path)]" }.joined(separator: "\n")
            userPrompt = refs + "\n\n" + userPrompt
        }

        let config = self.config
        let openAIClient = self.openAIClient
        let codexProvider = self.codexProvider
        let claudeProvider = self.claudeProvider
        let geminiProvider = self.geminiProvider
        let execController = self.executionController

        // Capture provider resolution closure so it can be used inside the Task
        let resolveWorker: @Sendable (AgentRole) -> any LLMProvider = { [self] role in
            self.workerProvider(for: role)
        }
        let defaultWorker = self.defaultWorkerProvider

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    execController?.beginScope(.swarm)
                    execController?.clearSwarmStopRequested()
                    execController?.clearSwarmPauseRequested()

                    func waitWhilePausedIfNeeded() async {
                        while execController?.swarmPauseRequested == true {
                            if execController?.swarmStopRequested == true { break }
                            try? await Task.sleep(nanoseconds: 120_000_000)
                        }
                    }

                    // --- Orchestration phase ---
                    let orchestrator = SwarmOrchestrator(
                        config: config,
                        openAIClient: openAIClient,
                        codexProvider: config.orchestratorBackend == .codex ? codexProvider : nil,
                        claudeProvider: config.orchestratorBackend == .claude
                            ? claudeProvider : nil,
                        geminiProvider: config.orchestratorBackend == .gemini ? geminiProvider : nil
                    )

                    var tasks = try await orchestrator.plan(
                        userPrompt: userPrompt, context: context)

                    // --- Auto post-code pipeline: append reviewer + testWriter if coder is present ---
                    if config.autoPostCodePipeline,
                        tasks.contains(where: { $0.role == .coder })
                    {
                        let maxOrder = tasks.map(\.order).max() ?? 0
                        let postOrder = maxOrder + 1
                        if config.enabledRoles.contains(.reviewer) {
                            tasks.append(
                                AgentTask(
                                    role: .reviewer,
                                    taskDescription:
                                        "Review all modified code. Look for bugs, style issues, and possible optimizations.",
                                    order: postOrder
                                ))
                        }
                        if config.enabledRoles.contains(.testWriter) {
                            tasks.append(
                                AgentTask(
                                    role: .testWriter,
                                    taskDescription:
                                        "Create test files for the modified code. Use XCTest for Swift, Jest/Vitest for Node, pytest for Python. Include unit, smoke, and integration tests where appropriate.",
                                    order: postOrder
                                ))
                        }
                        tasks.sort { $0.order < $1.order }
                    }

                    if tasks.isEmpty {
                        continuation.yield(
                            .textDelta(
                                "No tasks to execute. Try rephrasing your request."))
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }

                    // --- Execution phase ---
                    // Use a per-role worker runner when overrides are configured,
                    // otherwise use the simpler single-provider runner.
                    let hasOverrides = !config.workerBackendOverrides.isEmpty
                    let runner = SwarmWorkerRunner(
                        provider: defaultWorker,
                        isCancelled: execController.map { ec in
                            { ec.swarmStopRequested } as @Sendable () -> Bool
                        }
                    )

                    if hasOverrides {
                        // Per-role execution: run each task individually with its resolved provider
                        let sortedTasks = tasks.sorted { $0.order < $1.order }
                        var accumulatedOutput = ""
                        var isFirstTask = true

                        let orderGroups = Dictionary(grouping: sortedTasks, by: { $0.order })
                            .sorted { $0.key < $1.key }

                        for (_, groupTasks) in orderGroups {
                            if execController?.swarmStopRequested == true {
                                continuation.yield(
                                    .textDelta("\n\n[Swarm stopped by user.]\n"))
                                break
                            }
                            await waitWhilePausedIfNeeded()

                            for task in groupTasks {
                                if execController?.swarmStopRequested == true { break }
                                await waitWhilePausedIfNeeded()

                                let roleProvider = resolveWorker(task.role)
                                let roleRunner = SwarmWorkerRunner(
                                    provider: roleProvider,
                                    isCancelled: execController.map { ec in
                                        { ec.swarmStopRequested } as @Sendable () -> Bool
                                    }
                                )
                                let taskImageURLs =
                                    isFirstTask && !(imageURLs?.isEmpty ?? true)
                                    ? imageURLs : nil
                                let stream = roleRunner.run(
                                    tasks: [task], context: context,
                                    imageURLs: taskImageURLs)
                                for try await event in stream {
                                    await waitWhilePausedIfNeeded()
                                    continuation.yield(event)
                                    if case .textDelta(let d) = event {
                                        accumulatedOutput += d
                                    }
                                }
                                isFirstTask = false
                            }
                        }
                    } else {
                        // Standard execution: all tasks use the same default provider
                        let stream = runner.run(
                            tasks: tasks, context: context, imageURLs: imageURLs)
                        for try await event in stream {
                            await waitWhilePausedIfNeeded()
                            continuation.yield(event)
                        }
                    }

                    // --- Post-execution: run tests if testWriter was involved ---
                    if tasks.contains(where: { $0.role == .testWriter }),
                        let cmd = TestProjectDetector.testCommand(
                            workspacePath: context.workspacePath)
                    {
                        let maxRetries = config.maxPostCodeRetries
                        var attempt = 0
                        var allPassed = false

                        while attempt <= maxRetries {
                            await waitWhilePausedIfNeeded()
                            if execController?.swarmStopRequested == true { break }

                            let attemptLabel =
                                attempt > 0
                                ? " (attempt \(attempt + 1)/\(maxRetries + 1))" : ""
                            continuation.yield(
                                .textDelta(
                                    "\n\n## Running tests\(attemptLabel)\n\n"))

                            do {
                                let (output, status) = try await ProcessRunner.runCollecting(
                                    executable: cmd.executable,
                                    arguments: cmd.arguments,
                                    workingDirectory: context.workspacePath
                                )
                                for line in output {
                                    continuation.yield(.textDelta("[Test] \(line)\n"))
                                }

                                let fullOutput = output.joined(separator: "\n").lowercased()
                                let hasWarnings = fullOutput.contains("warning:")
                                allPassed = (status == 0) && !hasWarnings

                                if allPassed {
                                    continuation.yield(
                                        .textDelta(
                                            "\n**All tests passed. No errors or warnings.**\n"
                                        ))
                                    break
                                }

                                if attempt >= maxRetries {
                                    continuation.yield(
                                        .textDelta(
                                            "\n**Reached retry limit of \(maxRetries + 1) attempts.**\n"
                                        ))
                                    break
                                }

                                let failureReason =
                                    status != 0
                                    ? "Tests failed (exit code \(status))."
                                    : "There are warnings in the build/output."
                                continuation.yield(
                                    .textDelta(
                                        "\n**\(failureReason) Running Debugger...**\n\n"))

                                let debugTask = AgentTask(
                                    role: .debugger,
                                    taskDescription: """
                                        \(failureReason)
                                        Full output:
                                        \(output.joined(separator: "\n"))
                                        Fix all issues (errors, warnings, failed tests). Code must compile without warnings and all tests must pass.
                                        """,
                                    order: 1
                                )

                                let debugProvider = resolveWorker(.debugger)
                                let debugRunner = SwarmWorkerRunner(
                                    provider: debugProvider,
                                    isCancelled: execController.map { ec in
                                        { ec.swarmStopRequested } as @Sendable () -> Bool
                                    }
                                )
                                let debugStream = debugRunner.run(
                                    tasks: [debugTask], context: context)
                                for try await event in debugStream {
                                    await waitWhilePausedIfNeeded()
                                    continuation.yield(event)
                                }
                                attempt += 1
                            } catch {
                                continuation.yield(
                                    .textDelta(
                                        "\n**Unable to run tests: \(error.localizedDescription)**\n"
                                    ))
                                break
                            }
                        }
                    } else if tasks.contains(where: { $0.role == .testWriter }),
                        TestProjectDetector.detect(workspacePath: context.workspacePath)
                            == .unknown
                    {
                        continuation.yield(
                            .textDelta(
                                "\n**Project type not recognized for automatic test execution.**\n"
                            ))
                    }

                    // --- Post-execution: review loops ---
                    if config.enabledRoles.contains(.reviewer),
                        config.maxReviewLoops > 0,
                        tasks.contains(where: { $0.role == .coder })
                    {
                        let reviewProvider = resolveWorker(.reviewer)
                        let reviewRunner = SwarmWorkerRunner(
                            provider: reviewProvider,
                            isCancelled: execController.map { ec in
                                { ec.swarmStopRequested } as @Sendable () -> Bool
                            }
                        )
                        let coderProvider = resolveWorker(.coder)
                        let coderRunner = SwarmWorkerRunner(
                            provider: coderProvider,
                            isCancelled: execController.map { ec in
                                { ec.swarmStopRequested } as @Sendable () -> Bool
                            }
                        )

                        var reviewLoop = 0
                        while reviewLoop < config.maxReviewLoops {
                            await waitWhilePausedIfNeeded()
                            if execController?.swarmStopRequested == true { break }
                            reviewLoop += 1
                            continuation.yield(
                                .textDelta(
                                    "\n\n## Review loop \(reviewLoop)/\(config.maxReviewLoops): Quality check\n\n"
                                ))

                            let reviewTask = AgentTask(
                                role: .reviewer,
                                taskDescription:
                                    "Review all code in the workspace. List any remaining bugs, style issues, or missing optimizations. If everything is fine, respond only: 'No issues found.'",
                                order: 1
                            )
                            var reviewOutput = ""
                            let reviewStream = reviewRunner.run(
                                tasks: [reviewTask], context: context)
                            for try await event in reviewStream {
                                await waitWhilePausedIfNeeded()
                                continuation.yield(event)
                                if case .textDelta(let d) = event {
                                    reviewOutput += d
                                }
                            }

                            let lower = reviewOutput.lowercased()
                            let hasIssues =
                                lower.contains("bug")
                                || lower.contains("fix")
                                || lower.contains("issue")
                                || lower.contains("problem")
                                || lower.contains("error")
                                || (reviewOutput.count > 100
                                    && !lower.contains("no issues found")
                                    && !lower.contains("nessun problema"))
                            if !hasIssues { break }

                            continuation.yield(
                                .textDelta(
                                    "\n**Reviewer found issues. Running Coder for fixes...**\n\n"
                                ))

                            let fixTask = AgentTask(
                                role: .coder,
                                taskDescription:
                                    "Based on the Reviewer's report above, fix all identified issues (bugs, style, optimizations).",
                                order: 1
                            )
                            for try await event in coderRunner.run(
                                tasks: [fixTask], context: context)
                            {
                                await waitWhilePausedIfNeeded()
                                continuation.yield(event)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
