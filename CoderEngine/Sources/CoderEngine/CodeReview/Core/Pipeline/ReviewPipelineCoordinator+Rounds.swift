import Foundation

extension ReviewPipelineCoordinator {
    func runRounds(
        initialTasks: [CodeReviewMultiSwarmProvider.ReviewTask],
        extractionInconclusiveReason: String?,
        context: WorkspaceContext,
        config: MultiSwarmReviewConfig,
        againstRef: String?,
        resolvedScope: CodeReviewMultiSwarmProvider.ReviewFileScope,
        executionProvider: any LLMProvider,
        analysisProvider: any LLMProvider,
        execController: ExecutionController?,
        fileLockCoordinator: FileLockCoordinator,
        sessionState: CodeReviewSessionState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        isCancelled: @escaping @Sendable () -> Bool,
        waitWhilePaused: @escaping @Sendable () async -> Void
    ) async -> Bool {
        if initialTasks.isEmpty {
            if let extractionInconclusiveReason {
                continuation.yield(.textDelta("\n**Review complete (inconclusive).** Structured fix tasks were not produced: \(extractionInconclusiveReason)\n"))
                continuation.yield(.completed)
                continuation.finish()
                return true
            }
            return await runTerminalTestOnly(
                context: context,
                executionProvider: executionProvider,
                continuation: continuation,
                execController: execController,
                sessionState: sessionState,
                isCancelled: isCancelled,
                waitWhilePaused: waitWhilePaused
            )
        }

        var currentTasks = initialTasks
        var reviewRound = 0
        var finalReviewState: CodeReviewMultiSwarmProvider.ReviewFindingsState?
        var lastTestResult: CodeReviewMultiSwarmProvider.TestExecutionResult = .inconclusive(
            reason: "No test rounds executed."
        )

        reviewLoop: while reviewRound < config.maxReviewRounds {
            if isCancelled() { break reviewLoop }
            await waitWhilePaused()
            reviewRound += 1

            await sessionState.startRound(reviewRound)
            let sessionId = await sessionState.snapshot().sessionId
            for task in currentTasks {
                continuation.yield(.raw(type: "review-worker-plan", payload: [
                    "worker_id": task.id,
                    "description": task.description,
                    "severity": task.severity,
                    "fileCount": "\(task.files.count)",
                    "files_raw": task.files.joined(separator: "\n"),
                    "files": task.files.joined(separator: ", "),
                    "session_id": sessionId,
                ]))
            }
            continuation.yield(.raw(type: "review-fix-round", payload: [
                "round": "\(reviewRound)",
                "maxRounds": "\(config.maxReviewRounds)",
                "session_id": sessionId,
            ]))

            let fixSucceeded = await runPipelineFixStage(
                tasks: currentTasks,
                context: context,
                executionProvider: executionProvider,
                config: config,
                againstRef: againstRef,
                resolvedScope: resolvedScope,
                round: reviewRound,
                sessionState: sessionState,
                continuation: continuation,
                isCancelled: isCancelled,
                waitWhilePaused: waitWhilePaused
            )
            guard fixSucceeded else { return false }

            await sessionState.markRoundCompleted(reviewRound)
            await sessionState.markTestingStarted()
            lastTestResult = await CodeReviewMultiSwarmProvider.runTests(
                context: context,
                executionProvider: executionProvider,
                continuation: continuation,
                execController: execController,
                isCancelled: isCancelled,
                waitWhilePaused: waitWhilePaused
            )
            switch lastTestResult {
            case .passed:
                await sessionState.markTestResult(.passed, detail: "Tests passed")
            case .failed:
                await sessionState.markTestResult(.failed, detail: "Tests failed")
            case .inconclusive(let reason):
                await sessionState.markTestResult(.inconclusive, detail: reason)
            }

            let modifiedFiles = WorkspaceScanner.listUncommittedSourceFiles(
                workspacePath: context.workspacePath,
                excludedPaths: context.excludedPaths
            )
            if modifiedFiles.isEmpty {
                finalReviewState = .clean
                break reviewLoop
            }

            await sessionState.markReReviewStarted(round: reviewRound)
            let reReviewOutcome = await CodeReviewMultiSwarmProvider.runReReviewPhase(
                modifiedFiles: modifiedFiles,
                round: reviewRound,
                context: context,
                analysisProvider: analysisProvider,
                maxWorkers: config.maxWorkers,
                continuation: continuation,
                isCancelled: isCancelled,
                waitWhilePaused: waitWhilePaused
            )

            switch reReviewOutcome.findings {
            case .clean:
                finalReviewState = .clean
                break reviewLoop
            case .inconclusive(let reason):
                finalReviewState = .inconclusive(reason: reason)
                break reviewLoop
            case .issues:
                finalReviewState = .issues
                if reviewRound >= config.maxReviewRounds {
                    break reviewLoop
                }
            }

            let nextRoundTasks = CodeReviewMultiSwarmProvider.parseReviewTasks(
                from: reReviewOutcome.text,
                filesToReview: modifiedFiles,
                maxWorkers: config.maxWorkers
            )
            switch nextRoundTasks {
            case .tasks(let tasks) where !tasks.isEmpty:
                currentTasks = tasks
                let findings = tasks.map { task in
                    CodeReviewFinding.fromRawTask(
                        id: task.id,
                        description: task.description,
                        files: task.files,
                        severity: task.severity,
                        filePath: task.files.first
                    )
                }
                await sessionState.addFindings(findings)
            default:
                break reviewLoop
            }
        }

        if isCancelled() {
            continuation.yield(.textDelta("\n**Review cancelled.**\n"))
        } else {
            let testVerdict: String = switch lastTestResult {
            case .passed: "Tests passing."
            case .failed: "Tests failing."
            case .inconclusive(let reason): "Test status inconclusive (\(reason))."
            }
            let reviewVerdict: String = switch finalReviewState {
            case .clean: "Re-review clean."
            case .issues: "Re-review found remaining issues."
            case .inconclusive(let reason): "Re-review inconclusive (\(reason))."
            case nil: "Re-review not executed."
            }
            continuation.yield(.textDelta("\n---\n**Multi-swarm code review complete.** \(testVerdict) \(reviewVerdict)\n"))
        }
        continuation.yield(.completed)
        continuation.finish()
        return true
    }

    func runTerminalTestOnly(
        context: WorkspaceContext,
        executionProvider: any LLMProvider,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        execController: ExecutionController?,
        sessionState: CodeReviewSessionState,
        isCancelled: @escaping @Sendable () -> Bool,
        waitWhilePaused: @escaping @Sendable () async -> Void
    ) async -> Bool {
        await sessionState.markTestingStarted()
        let testResult = await CodeReviewMultiSwarmProvider.runTests(
            context: context,
            executionProvider: executionProvider,
            continuation: continuation,
            execController: execController,
            isCancelled: isCancelled,
            waitWhilePaused: waitWhilePaused
        )
        switch testResult {
        case .passed:
            await sessionState.markTestResult(.passed, detail: "Tests passed")
        case .failed:
            await sessionState.markTestResult(.failed, detail: "Tests failed")
        case .inconclusive(let reason):
            await sessionState.markTestResult(.inconclusive, detail: reason)
        }
        continuation.yield(.completed)
        continuation.finish()
        return true
    }
}
