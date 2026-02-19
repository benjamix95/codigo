import Foundation

/// Provider LLM che coordina un swarm di agenti specializzati tramite orchestratore
public final class AgentSwarmProvider: LLMProvider, @unchecked Sendable {
    public let id = "agent-swarm"
    public let displayName = "Agent Swarm"

    private let config: SwarmConfig
    private let openAIClient: OpenAICompletionsClient?
    private let codexProvider: CodexCLIProvider
    private let claudeProvider: ClaudeCLIProvider?
    private let executionController: ExecutionController?

    public init(
        config: SwarmConfig,
        openAIClient: OpenAICompletionsClient?,
        codexProvider: CodexCLIProvider,
        claudeProvider: ClaudeCLIProvider? = nil,
        executionController: ExecutionController? = nil
    ) {
        self.config = config
        self.openAIClient = openAIClient
        self.codexProvider = codexProvider
        self.claudeProvider = claudeProvider
        self.executionController = executionController
    }

    public func isAuthenticated() -> Bool {
        let workerOk: Bool
        switch config.workerBackend {
        case .codex: workerOk = codexProvider.isAuthenticated()
        case .claude: workerOk = claudeProvider?.isAuthenticated() ?? false
        }
        guard workerOk else { return false }

        switch config.orchestratorBackend {
        case .openai: return openAIClient != nil
        case .codex: return codexProvider.isAuthenticated()
        case .claude: return claudeProvider?.isAuthenticated() ?? false
        }
    }

    private var workerProvider: any LLMProvider {
        switch config.workerBackend {
        case .claude:
            if let claude = claudeProvider, claude.isAuthenticated() { return claude }
            return codexProvider
        case .codex:
            return codexProvider
        }
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        var userPrompt = prompt
        if let urls = imageURLs, !urls.isEmpty {
            let refs = urls.map { "[Immagine: \($0.path)]" }.joined(separator: "\n")
            userPrompt = refs + "\n\n" + userPrompt
        }
        let config = self.config
        let openAIClient = self.openAIClient
        let codexProvider = self.codexProvider
        let claudeProvider = self.claudeProvider
        let worker = self.workerProvider

        let execController = executionController
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
                    let orchestrator = SwarmOrchestrator(
                        config: config,
                        openAIClient: openAIClient,
                        codexProvider: config.orchestratorBackend == .codex ? codexProvider : nil,
                        claudeProvider: config.orchestratorBackend == .claude ? claudeProvider : nil
                    )
                    var tasks = try await orchestrator.plan(userPrompt: userPrompt, context: context)

                    if config.autoPostCodePipeline, tasks.contains(where: { $0.role == .coder }) {
                        let maxOrder = tasks.map(\.order).max() ?? 0
                        let postOrder = maxOrder + 1
                        if config.enabledRoles.contains(.reviewer) {
                            tasks.append(AgentTask(
                                role: .reviewer,
                                taskDescription: "Revisiona tutto il codice modificato. Cerca bug, problemi di stile, ottimizzazioni possibili.",
                                order: postOrder
                            ))
                        }
                        if config.enabledRoles.contains(.testWriter) {
                            tasks.append(AgentTask(
                                role: .testWriter,
                                taskDescription: "Crea file di test per il codice modificato. Usa XCTest per Swift, Jest/Vitest per Node, pytest per Python. Includi unit test, smoke test e integration test dove appropriato.",
                                order: postOrder
                            ))
                        }
                        tasks.sort { $0.order < $1.order }
                    }

                    if tasks.isEmpty {
                        continuation.yield(.textDelta("Nessun task da eseguire. Prova a riformulare la richiesta."))
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }

                    let runner = SwarmWorkerRunner(
                        provider: worker,
                        isCancelled: execController.map { ec in { ec.swarmStopRequested } as @Sendable () -> Bool }
                    )
                    let stream = runner.run(tasks: tasks, context: context, imageURLs: imageURLs)

                    for try await event in stream {
                        await waitWhilePausedIfNeeded()
                        continuation.yield(event)
                    }

                    if tasks.contains(where: { $0.role == .testWriter }),
                       let cmd = TestProjectDetector.testCommand(workspacePath: context.workspacePath) {
                        let maxRetries = config.maxPostCodeRetries
                        var attempt = 0
                        var allPassed = false

                        while attempt <= maxRetries {
                            await waitWhilePausedIfNeeded()
                            if execController?.swarmStopRequested == true { break }
                            continuation.yield(.textDelta("\n\n## Esecuzione test\(attempt > 0 ? " (tentativo \(attempt + 1)/\(maxRetries + 1))" : "")\n\n"))
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
                                    continuation.yield(.textDelta("\n**Test completati con successo. Nessun errore o warning.**\n"))
                                    break
                                }

                                if attempt >= maxRetries {
                                    continuation.yield(.textDelta("\n**Raggiunto il limite di \(maxRetries + 1) tentativi.**\n"))
                                    break
                                }

                                let failureReason = status != 0
                                    ? "I test sono falliti (exit code \(status))."
                                    : "Ci sono warning nel build/output."
                                continuation.yield(.textDelta("\n**\(failureReason) Esecuzione Debugger...**\n\n"))

                                let debugTask = AgentTask(
                                    role: .debugger,
                                    taskDescription: """
                                    \(failureReason)
                                    Output completo:
                                    \(output.joined(separator: "\n"))
                                    Correggi tutti i problemi (errori, warning, test falliti). Il codice deve compilare senza warning e tutti i test devono passare.
                                    """,
                                    order: 1
                                )
                                let debugStream = runner.run(tasks: [debugTask], context: context)
                                for try await event in debugStream {
                                    await waitWhilePausedIfNeeded()
                                    continuation.yield(event)
                                }
                                attempt += 1
                            } catch {
                                continuation.yield(.textDelta("\n**Impossibile eseguire i test: \(error.localizedDescription)**\n"))
                                break
                            }
                        }
                    } else if tasks.contains(where: { $0.role == .testWriter }),
                              TestProjectDetector.detect(workspacePath: context.workspacePath) == .unknown {
                        continuation.yield(.textDelta("\n**Tipo progetto non riconosciuto per esecuzione test automatica.**\n"))
                    }

                    if config.enabledRoles.contains(.reviewer), config.maxReviewLoops > 0, tasks.contains(where: { $0.role == .coder }) {
                        var reviewLoop = 0
                        while reviewLoop < config.maxReviewLoops {
                            await waitWhilePausedIfNeeded()
                            if execController?.swarmStopRequested == true { break }
                            reviewLoop += 1
                            continuation.yield(.textDelta("\n\n## Review loop \(reviewLoop)/\(config.maxReviewLoops): Verifica qualità\n\n"))
                            let reviewTask = AgentTask(
                                role: .reviewer,
                                taskDescription: "Revisiona tutto il codice nel workspace. Elenca eventuali bug residui, problemi di stile, ottimizzazioni mancanti. Se tutto è ok, rispondi solo: 'Nessun problema rilevato.'",
                                order: 1
                            )
                            var reviewOutput = ""
                            let reviewStream = runner.run(tasks: [reviewTask], context: context)
                            for try await event in reviewStream {
                                await waitWhilePausedIfNeeded()
                                continuation.yield(event)
                                if case .textDelta(let d) = event { reviewOutput += d }
                            }
                            let hasIssues = reviewOutput.lowercased().contains("priorità") || reviewOutput.lowercased().contains("bug") ||
                                reviewOutput.lowercased().contains("correggere") || reviewOutput.lowercased().contains("problema") ||
                                (reviewOutput.count > 100 && !reviewOutput.lowercased().contains("nessun problema rilevato"))
                            if !hasIssues { break }
                            continuation.yield(.textDelta("\n**Reviewer ha trovato issue. Esecuzione Coder per correzioni...**\n\n"))
                            let fixTask = AgentTask(
                                role: .coder,
                                taskDescription: "In base al report del Reviewer precedente, correggi tutti i problemi indicati (bug, stile, ottimizzazioni).",
                                order: 1
                            )
                            for try await event in runner.run(tasks: [fixTask], context: context) {
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
