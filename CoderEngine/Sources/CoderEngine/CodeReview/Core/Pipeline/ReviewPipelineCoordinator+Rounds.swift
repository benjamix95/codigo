import Foundation

extension ReviewPipelineCoordinator {
    func runRounds(
        initialTasks: [CodeReviewMultiSwarmProvider.ReviewTask],
        context: WorkspaceContext,
        config: MultiSwarmReviewConfig,
        againstRef: String?,
        resolvedScope: CodeReviewMultiSwarmProvider.ReviewFileScope,
        staticAnalysisProvider: any LLMProvider,
        staticExecutionProvider: any LLMProvider,
        runtimeResolver: CodeReviewRuntimeResolver?,
        execController: ExecutionController?,
        fileLockCoordinator: FileLockCoordinator,
        sessionState: CodeReviewSessionState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        isCancelled: @escaping @Sendable () -> Bool,
        waitWhilePaused: @escaping @Sendable () async -> Void
    ) async -> CodeReviewMultiSwarmProvider.ReviewPipelineRunOutcome {
        if initialTasks.isEmpty {
            return await runTerminalTestOnly(
                context: context,
                staticConfig: config,
                staticExecutionProvider: staticExecutionProvider,
                runtimeResolver: runtimeResolver,
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
        var finalFailureReason: String?
        var lastTestResult: CodeReviewMultiSwarmProvider.TestExecutionResult = .inconclusive(
            reason: "No test rounds executed."
        )

        reviewLoop: while true {
            let runtimeResources = await currentRuntimeResources(
                staticConfig: config,
                staticAnalysisProvider: staticAnalysisProvider,
                staticExecutionProvider: staticExecutionProvider,
                runtimeResolver: runtimeResolver,
                sessionState: sessionState
            )
            let runtimeConfig = runtimeResources.config
            guard reviewRound < runtimeConfig.maxReviewRounds else {
                break reviewLoop
            }
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
                "maxRounds": "\(runtimeConfig.maxReviewRounds)",
                "session_id": sessionId,
            ]))

            let fixSucceeded = await runPipelineFixStage(
                tasks: currentTasks,
                context: context,
                executionProvider: runtimeResources.executionProvider,
                config: runtimeConfig,
                againstRef: againstRef,
                resolvedScope: resolvedScope,
                fileLockCoordinator: fileLockCoordinator,
                round: reviewRound,
                sessionState: sessionState,
                continuation: continuation,
                isCancelled: isCancelled,
                waitWhilePaused: waitWhilePaused
            )
            guard fixSucceeded else {
                return .failed(reason: "Review fix stage failed.")
            }

            await sessionState.markRoundCompleted(reviewRound)
            await sessionState.markTestingStarted()
            lastTestResult = await CodeReviewMultiSwarmProvider.runTests(
                context: context,
                executionProvider: runtimeResources.executionProvider,
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

            let allowedScopeFiles = Set((await sessionState.snapshot().scope?.files) ?? [])
            let modifiedFiles = scopedModifiedFilesForReReview(
                workspacePath: context.workspacePath,
                excludedPaths: context.excludedPaths,
                allowedScopeFiles: allowedScopeFiles
            )
            if modifiedFiles.isEmpty {
                finalFailureReason = "Fix stage completed without producing any in-scope workspace changes."
                finalReviewState = .issues
                break reviewLoop
            }

            await sessionState.markReReviewStarted(round: reviewRound)
            let reReviewOutcome = await CodeReviewMultiSwarmProvider.runReReviewPhase(
                modifiedFiles: modifiedFiles,
                round: reviewRound,
                context: context,
                analysisProvider: runtimeResources.analysisProvider,
                maxWorkers: runtimeConfig.maxWorkers,
                continuation: continuation,
                isCancelled: isCancelled,
                waitWhilePaused: waitWhilePaused
            )

            switch reReviewOutcome.findings {
            case .clean:
                await sessionState.markOpenFindingsAsFixApplied(
                    in: Set(modifiedFiles)
                )
                let hasRemainingOpenFindings = !(await sessionState.snapshot()).openFindings.isEmpty
                finalReviewState = hasRemainingOpenFindings ? .issues : .clean
                if !hasRemainingOpenFindings {
                    break reviewLoop
                }
                finalFailureReason = "Some review findings remain open outside the files modified in the current round."
                break reviewLoop
            case .inconclusive(let reason):
                finalReviewState = .inconclusive(reason: reason)
                break reviewLoop
            case .issues:
                finalReviewState = .issues
                if reviewRound >= runtimeConfig.maxReviewRounds {
                    break reviewLoop
                }
            }

            let nextRoundTasks = CodeReviewMultiSwarmProvider.parseReviewTasks(
                from: reReviewOutcome.text,
                filesToReview: modifiedFiles,
                maxWorkers: runtimeConfig.maxWorkers
            )
            switch nextRoundTasks {
            case .tasks(let tasks) where !tasks.isEmpty:
                currentTasks = tasks
                let findings = tasks.map { task in
                    CodeReviewFinding.fromRawTask(
                        id: nextFindingID(taskID: task.id, round: reviewRound),
                        description: task.description,
                        files: task.files,
                        severity: task.severity,
                        filePath: task.files.first
                    )
                }
                await sessionState.replaceOpenFindings(
                    in: Set(modifiedFiles),
                    with: findings
                )
            default:
                finalFailureReason = "Re-review reported issues but produced no actionable follow-up tasks."
                break reviewLoop
            }
        }

        if isCancelled() {
            continuation.yield(.textDelta("\n**Review cancelled.**\n"))
            continuation.yield(.completed)
            continuation.finish()
            return .cancelled
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
            let failureSuffix = finalFailureReason.map { " Failure: \($0)." } ?? ""
            continuation.yield(.textDelta("\n---\n**Multi-swarm code review complete.** \(testVerdict) \(reviewVerdict)\(failureSuffix)\n"))
        }
        continuation.yield(.completed)
        continuation.finish()
        if let finalFailureReason {
            return .failed(reason: finalFailureReason)
        }
        switch finalReviewState {
        case .clean?:
            switch lastTestResult {
            case .passed:
                return .completed
            case .failed, .inconclusive:
                return .failed(reason: "Review finished with unresolved test failures or inconclusive tests.")
            }
        case .issues?:
            return .failed(reason: "Review finished with remaining open findings.")
        case .inconclusive(let reason)?:
            return .failed(reason: "Review ended inconclusively: \(reason)")
        case nil:
            switch lastTestResult {
            case .passed:
                return .completed
            case .failed:
                return .failed(reason: "Tests failed.")
            case .inconclusive(let reason):
                return .failed(reason: "Tests were inconclusive: \(reason)")
            }
        }
    }

    func runTerminalTestOnly(
        context: WorkspaceContext,
        staticConfig: MultiSwarmReviewConfig,
        staticExecutionProvider: any LLMProvider,
        runtimeResolver: CodeReviewRuntimeResolver?,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        execController: ExecutionController?,
        sessionState: CodeReviewSessionState,
        isCancelled: @escaping @Sendable () -> Bool,
        waitWhilePaused: @escaping @Sendable () async -> Void
    ) async -> CodeReviewMultiSwarmProvider.ReviewPipelineRunOutcome {
        let runtimeResources = await currentRuntimeResources(
            staticConfig: staticConfig,
            staticAnalysisProvider: staticExecutionProvider,
            staticExecutionProvider: staticExecutionProvider,
            runtimeResolver: runtimeResolver,
            sessionState: sessionState
        )
        await sessionState.markTestingStarted()
        let testResult = await CodeReviewMultiSwarmProvider.runTests(
            context: context,
            executionProvider: runtimeResources.executionProvider,
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
        switch testResult {
        case .passed:
            return .completed
        case .failed:
            return .failed(reason: "Tests failed.")
        case .inconclusive(let reason):
            return .failed(reason: "Tests were inconclusive: \(reason)")
        }
    }

    private func scopedModifiedFilesForReReview(
        workspacePath: URL,
        excludedPaths: [String],
        allowedScopeFiles: Set<String>
    ) -> [String] {
        let modifiedFiles = WorkspaceScanner.listUncommittedSourceFiles(
            workspacePath: workspacePath,
            excludedPaths: excludedPaths
        )
        guard !allowedScopeFiles.isEmpty else { return modifiedFiles }
        return modifiedFiles.filter { allowedScopeFiles.contains($0) }
    }

    private func nextFindingID(taskID: String, round: Int) -> String {
        "r\(round)-\(taskID)"
    }
}
