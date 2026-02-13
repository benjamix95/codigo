import Foundation

/// Provider LLM che coordina un swarm di agenti specializzati tramite orchestratore
public final class AgentSwarmProvider: LLMProvider, @unchecked Sendable {
    public let id = "agent-swarm"
    public let displayName = "Agent Swarm"

    private let config: SwarmConfig
    private let openAIClient: OpenAICompletionsClient?
    private let codexProvider: CodexCLIProvider

    public init(
        config: SwarmConfig,
        openAIClient: OpenAICompletionsClient?,
        codexProvider: CodexCLIProvider
    ) {
        self.config = config
        self.openAIClient = openAIClient
        self.codexProvider = codexProvider
    }

    public func isAuthenticated() -> Bool {
        guard codexProvider.isAuthenticated() else { return false }
        switch config.orchestratorBackend {
        case .openai:
            return openAIClient != nil
        case .codex:
            return true
        }
    }

    public func send(prompt: String, context: WorkspaceContext) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let config = self.config
        let openAIClient = self.openAIClient
        let codexProvider = self.codexProvider

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let orchestrator = SwarmOrchestrator(
                        config: config,
                        openAIClient: openAIClient,
                        codexProvider: config.orchestratorBackend == .codex ? codexProvider : nil
                    )
                    var tasks = try await orchestrator.plan(userPrompt: prompt, context: context)

                    // Pipeline QA automatica: appendi Reviewer e TestWriter dopo Coder
                    if config.autoPostCodePipeline, tasks.contains(where: { $0.role == .coder }) {
                        let maxOrder = tasks.map(\.order).max() ?? 0
                        if config.enabledRoles.contains(.reviewer) {
                            tasks.append(AgentTask(
                                role: .reviewer,
                                taskDescription: "Revisiona tutto il codice modificato. Cerca bug, problemi di stile, ottimizzazioni possibili.",
                                order: maxOrder + 1
                            ))
                        }
                        if config.enabledRoles.contains(.testWriter) {
                            tasks.append(AgentTask(
                                role: .testWriter,
                                taskDescription: "Crea file di test per il codice modificato. Usa XCTest per Swift, Jest/Vitest per Node, pytest per Python. Includi unit test, smoke test e integration test dove appropriato.",
                                order: maxOrder + 2
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

                    let runner = SwarmWorkerRunner(codexProvider: codexProvider)
                    let stream = runner.run(tasks: tasks, context: context)

                    for try await event in stream {
                        continuation.yield(event)
                    }

                    // Esecuzione test automatica e loop fino a successo (test OK, no errori, no warning)
                    if tasks.contains(where: { $0.role == .testWriter }),
                       let cmd = TestProjectDetector.testCommand(workspacePath: context.workspacePath) {
                        let maxRetries = config.maxPostCodeRetries
                        var attempt = 0
                        var allPassed = false

                        while attempt <= maxRetries {
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

                                // Debugger per correggere
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

                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
