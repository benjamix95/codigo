import Foundation

/// LLM provider that coordinates a swarm of specialized agents via orchestrator
public final class SwarmRuntimeProvider: LLMProvider, @unchecked Sendable {
    public let id = "swarm-runtime-internal"
    public let displayName = "Agent Swarm"
    public var attachmentCapabilities: ProviderAttachmentCapabilities {
        workerProvider.attachmentCapabilities
    }

    private let config: SwarmConfig
    private let orchestratorProvider: any LLMProvider
    private let workerProvider: any LLMProvider
    private let executionController: ExecutionController?

    public init(
        config: SwarmConfig,
        orchestratorProvider: any LLMProvider,
        workerProvider: any LLMProvider,
        executionController: ExecutionController? = nil
    ) {
        self.config = config
        self.orchestratorProvider = orchestratorProvider
        self.workerProvider = workerProvider
        self.executionController = executionController
    }

    public func isAuthenticated() -> Bool {
        orchestratorProvider.isAuthenticated() && workerProvider.isAuthenticated()
    }

    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil)
        async throws -> AsyncThrowingStream<StreamEvent, Error>
    {
        var userPrompt = prompt
        if let urls = imageURLs, !urls.isEmpty {
            let refs = urls.map { "[Image: \($0.path)]" }.joined(separator: "\n")
            userPrompt = refs + "\n\n" + userPrompt
        }
        let config = self.config
        let orchestratorProvider = self.orchestratorProvider
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
                        provider: orchestratorProvider
                    )
                    var tasks = try await orchestrator.plan(
                        userPrompt: userPrompt, context: context)

                    if config.autoPostCodePipeline, tasks.contains(where: { $0.role == .coder }) {
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
                                        "Create test files for the modified code. Use XCTest for Swift, Jest/Vitest for Node, pytest for Python. Include unit tests, smoke tests, and integration tests where appropriate.",
                                    order: postOrder
                                ))
                        }
                        tasks.sort { $0.order < $1.order }
                    }

                    if tasks.isEmpty {
                        continuation.yield(
                            .textDelta("No tasks to execute. Try rephrasing the request.")
                        )
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }

                    let runner = SwarmWorkerRunner(
                        provider: worker,
                        isCancelled: execController.map { ec in
                            { ec.swarmStopRequested } as @Sendable () -> Bool
                        }
                    )
                    let stream = runner.run(tasks: tasks, context: context, imageURLs: imageURLs)

                    for try await event in stream {
                        await waitWhilePausedIfNeeded()
                        continuation.yield(event)
                    }

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
                            continuation.yield(
                                .textDelta(
                                    "\n\n## Running tests\(attempt > 0 ? " (attempt \(attempt + 1)/\(maxRetries + 1))" : "")\n\n"
                                ))
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
                                            "\n**Tests completed successfully. No errors or warnings.**\n"
                                        ))
                                    break
                                }

                                if attempt >= maxRetries {
                                    continuation.yield(
                                        .textDelta(
                                            "\n**Reached the limit of \(maxRetries + 1) attempts.**\n"
                                        ))
                                    break
                                }

                                let failureReason =
                                    status != 0
                                    ? "Tests failed (exit code \(status))."
                                    : "There are warnings in the build/output."
                                continuation.yield(
                                    .textDelta("\n**\(failureReason) Running Debugger...**\n\n"))

                                let debugTask = AgentTask(
                                    role: .debugger,
                                    taskDescription: """
                                        \(failureReason)
                                        Full output:
                                        \(output.joined(separator: "\n"))
                                        Fix all issues (errors, warnings, failing tests). The code must compile without warnings and all tests must pass.
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
                                continuation.yield(
                                    .textDelta(
                                        "\n**Unable to run tests: \(error.localizedDescription)**\n"
                                    ))
                                break
                            }
                        }
                    } else if tasks.contains(where: { $0.role == .testWriter }),
                        TestProjectDetector.detect(workspacePath: context.workspacePath) == .unknown
                    {
                        continuation.yield(
                            .textDelta(
                                "\n**Project type not recognized for automatic test execution.**\n"
                            ))
                    }

                    if config.enabledRoles.contains(.reviewer), config.maxReviewLoops > 0,
                        tasks.contains(where: { $0.role == .coder })
                    {
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
                                    "Review all code in the workspace. List any remaining bugs, style issues, missing optimizations. If everything is fine, respond only: 'No issues found.'",
                                order: 1
                            )
                            var reviewOutput = ""
                            let reviewStream = runner.run(tasks: [reviewTask], context: context)
                            for try await event in reviewStream {
                                await waitWhilePausedIfNeeded()
                                continuation.yield(event)
                                if case .textDelta(let d) = event { reviewOutput += d }
                            }
                            let hasIssues =
                                reviewOutput.lowercased().contains("priority")
                                || reviewOutput.lowercased().contains("bug")
                                || reviewOutput.lowercased().contains("fix")
                                || reviewOutput.lowercased().contains("issue")
                                || (reviewOutput.count > 100
                                    && !reviewOutput.lowercased().contains(
                                        "no issues found"))
                            if !hasIssues { break }
                            continuation.yield(
                                .textDelta(
                                    "\n**Reviewer found issues. Running Coder for fixes...**\n\n"
                                ))
                            let fixTask = AgentTask(
                                role: .coder,
                                taskDescription:
                                    "Based on the previous Reviewer report, fix all indicated issues (bugs, style, optimizations).",
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
