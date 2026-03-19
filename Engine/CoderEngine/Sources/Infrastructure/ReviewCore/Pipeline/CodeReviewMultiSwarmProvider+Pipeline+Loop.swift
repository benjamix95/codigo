import Foundation

extension CodeReviewMultiSwarmProvider {
    static func executeReviewLoop(
        tasks initialTasks: [ReviewTask],
        extractionInconclusiveReason: String?,
        config: MultiSwarmReviewConfig,
        context: WorkspaceContext,
        executionProvider: any LLMProvider,
        analysisProvider: any LLMProvider,
        fileLockCoordinator: FileLockCoordinator,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        execController: ExecutionController?,
        isCancelled: @escaping @Sendable () -> Bool,
        waitWhilePaused: @escaping @Sendable () async -> Void
    ) async {
        for task in initialTasks {
            continuation.yield(.raw(type: "review-worker-plan", payload: [
                "worker_id": task.id,
                "description": task.description,
                "severity": task.severity,
                "fileCount": "\(task.files.count)",
                "files_raw": task.files.joined(separator: "\n"),
                "files": task.files.prefix(5).joined(separator: ", ")
                    + (task.files.count > 5 ? " (+\(task.files.count - 5) more)" : "")
            ]))
        }

        if config.enabledPhases == .analysisOnly {
            continuation.yield(.textDelta("\n---\n**Analysis complete.** (Analysis-only mode)\n"))
            continuation.yield(.completed)
            continuation.finish()
            return
        }

        if initialTasks.isEmpty {
            if let extractionInconclusiveReason {
                continuation.yield(.textDelta(
                    "\n**Review complete (inconclusive).** Structured fix tasks were not produced: \(extractionInconclusiveReason)\n"
                ))
                continuation.yield(.completed)
                continuation.finish()
                return
            }
            continuation.yield(.textDelta("\n**No actionable fix tasks.** Running tests...\n"))
            let testResult = await Self.runTests(
                context: context,
                executionProvider: executionProvider,
                continuation: continuation,
                execController: execController,
                isCancelled: isCancelled,
                waitWhilePaused: waitWhilePaused
            )
            let verdict = switch testResult {
            case .passed: "No issues found, tests pass."
            case .failed: "Tests have issues."
            case .inconclusive(let reason): "Tests status inconclusive: \(reason)"
            }
            continuation.yield(.textDelta("\n---\n**Review complete.** \(verdict)\n"))
            continuation.yield(.completed)
            continuation.finish()
            return
        }

        continuation.yield(.textDelta("\n**Workers planned:** \(initialTasks.count) (max \(config.maxWorkers))\n\n"))

        var reviewRound = 0
        var currentTasks = initialTasks
        var lastTestResult: TestExecutionResult = .inconclusive(reason: "No test rounds executed.")
        var finalReviewState: ReviewFindingsState?

        reviewLoop: while reviewRound < config.maxReviewRounds {
            if isCancelled() { break reviewLoop }
            await waitWhilePaused()
            reviewRound += 1

            continuation.yield(.raw(type: "review-fix-round", payload: [
                "round": "\(reviewRound)",
                "maxRounds": "\(config.maxReviewRounds)"
            ]))

            continuation.yield(.textDelta("\n### Fix Phase (Round \(reviewRound)/\(config.maxReviewRounds))\n\n"))
            await Self.runParallelFixPhase(
                tasks: currentTasks,
                context: context,
                executionProvider: executionProvider,
                fileLockCoordinator: fileLockCoordinator,
                continuation: continuation,
                isCancelled: isCancelled,
                waitWhilePaused: waitWhilePaused
            )

            if isCancelled() { break reviewLoop }

            continuation.yield(.textDelta("\n### Test Phase\n\n"))
            let testResult = await Self.runTests(
                context: context,
                executionProvider: executionProvider,
                continuation: continuation,
                execController: execController,
                isCancelled: isCancelled,
                waitWhilePaused: waitWhilePaused
            )
            lastTestResult = testResult
            let testPassed: Bool
            switch testResult {
            case .passed:
                testPassed = true
            case .inconclusive(let reason):
                continuation.yield(.textDelta("\n**Review validation incomplete:** \(reason)\n"))
                continuation.yield(.textDelta("Continuing with next review round...\n"))
                testPassed = false
            case .failed:
                testPassed = false
            }

            let modifiedFiles = WorkspaceScanner.listUncommittedSourceFiles(
                workspacePath: context.workspacePath,
                excludedPaths: context.excludedPaths
            )
            if modifiedFiles.isEmpty {
                continuation.yield(.textDelta("No modified files remain. Review complete.\n"))
                finalReviewState = .clean
                break reviewLoop
            }

            if isCancelled() { break reviewLoop }
            let isFinalRound = reviewRound >= config.maxReviewRounds
            continuation.yield(.textDelta(
                "\n### Re-Review Phase (Round \(reviewRound)\(isFinalRound ? " - Final Verification" : ""))\n\n"
            ))
            let reReviewOutcome = await Self.runReReviewPhase(
                modifiedFiles: modifiedFiles,
                round: reviewRound,
                context: context,
                analysisProvider: analysisProvider,
                maxWorkers: config.maxWorkers,
                continuation: continuation,
                isCancelled: isCancelled,
                waitWhilePaused: waitWhilePaused
            )

            if isCancelled() { break reviewLoop }
            switch reReviewOutcome.findings {
            case .clean:
                continuation.yield(.textDelta("\n**All clear.** No new issues found.\n"))
                finalReviewState = .clean
                break reviewLoop
            case .inconclusive(let reason):
                continuation.yield(.textDelta("\n**Re-review inconclusive:** \(reason). Review stopped to avoid unsafe fallback.\n"))
                finalReviewState = .inconclusive(reason: reason)
                break reviewLoop
            case .issues:
                finalReviewState = .issues
                if isFinalRound {
                    continuation.yield(.textDelta(
                        "\n**Issues remain after final round.** Maximum rounds reached; manual follow-up required.\n"
                    ))
                    break reviewLoop
                }
            }

            let nextRoundTasks = Self.parseReviewTasks(
                from: reReviewOutcome.text,
                filesToReview: modifiedFiles,
                maxWorkers: config.maxWorkers
            )
            switch nextRoundTasks {
            case .tasks(let newTasks) where !newTasks.isEmpty:
                currentTasks = newTasks
            case .tasks, .noFixes:
                let reason = "Re-review flagged issues but returned no actionable tasks for another round."
                continuation.yield(.textDelta(
                    "\n**Re-review inconsistent:** \(reason) Stopping for safety.\n"
                ))
                finalReviewState = .inconclusive(reason: reason)
                break reviewLoop
            case .noPayload(let reason):
                continuation.yield(.textDelta("\n**Re-review payload missing: \(reason).** Unable to safely continue without validated tasks.\n"))
                finalReviewState = .inconclusive(reason: reason)
                break reviewLoop
            case .invalidJSON(let reason):
                continuation.yield(.textDelta("\n**Re-review payload invalid: \(reason)** Stopping for safety.\n"))
                finalReviewState = .inconclusive(reason: "Re-review payload invalid: \(reason)")
                break reviewLoop
            }

            continuation.yield(.textDelta(
                "\n**New issues found.** Proceeding to fix round \(reviewRound + 1) with \(currentTasks.count) worker(s)...\(testPassed ? " (tests pass but code issues remain)" : "")\n"
            ))
        }

        if isCancelled() {
            continuation.yield(.textDelta("\n**Review cancelled.**\n"))
        } else {
            let testVerdict: String = switch lastTestResult {
            case .passed: "Tests passing."
            case .failed: "Tests failing — manual intervention may be needed."
            case .inconclusive(let reason): "Test status inconclusive (\(reason))."
            }
            let reviewVerdict: String = switch finalReviewState {
            case .clean: "Re-review clean."
            case .issues: "Re-review found remaining issues."
            case .inconclusive(let reason): "Re-review inconclusive (\(reason))."
            case nil: "Re-review not executed."
            }
            continuation.yield(.textDelta(
                "\n---\n**Multi-swarm code review complete.** \(testVerdict) \(reviewVerdict)\n"
            ))
        }
        continuation.yield(.completed)
        continuation.finish()
    }
}
