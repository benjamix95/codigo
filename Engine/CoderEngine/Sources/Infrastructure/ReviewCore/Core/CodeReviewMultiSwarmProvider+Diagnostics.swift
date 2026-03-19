import Foundation

extension CodeReviewMultiSwarmProvider {
    static func findingsContainIssues(_ text: String) -> ReviewFindingsState {
        guard let response = ReviewProviderRustBridge.reduce(
            operation: "classify_review_outcome",
            text: text
        ) else {
            return .inconclusive(reason: "Rust review provider reducer unavailable.")
        }
        switch response.findingsState {
        case "issues":
            return .issues
        case "clean":
            return .clean
        case "inconclusive":
            return .inconclusive(
                reason: response.reason ?? "No robust issue indicators found in re-review output."
            )
        default:
            return .inconclusive(reason: "Rust review provider reducer returned an unsupported result.")
        }
    }

    static func runTests(
        context: WorkspaceContext,
        executionProvider: any LLMProvider,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        execController: ExecutionController?,
        isCancelled: @Sendable @escaping () -> Bool,
        waitWhilePaused: @Sendable @escaping () async -> Void
    ) async -> TestExecutionResult {
        guard let cmd = TestProjectDetector.testCommand(workspacePath: context.workspacePath) else {
            continuation.yield(.textDelta("Project type not recognized for automatic test execution.\n"))
            return .inconclusive(reason: "Project test command could not be resolved.")
        }

        let maxAttempts = 2
        for attempt in 0..<maxAttempts {
            if isCancelled() { return .failed }
            await waitWhilePaused()

            continuation.yield(.textDelta("Running tests\(attempt > 0 ? " (retry \(attempt))" : "")...\n"))

            do {
                let (output, status) = try await ProcessRunner.runCollecting(
                    executable: cmd.executable,
                    arguments: cmd.arguments,
                    workingDirectory: context.workspacePath,
                    executionController: execController,
                    scope: .review
                )

                let fullOutput = output.joined(separator: "\n")
                let lower = fullOutput.lowercased()
                let hasTestFailures = hasTestFailureSignal(in: lower)
                let passed = (status == 0) && !hasTestFailures

                if passed {
                    continuation.yield(.textDelta("**Tests passed successfully.**\n"))
                    return .passed
                }

                let tailLines = output.suffix(20).joined(separator: "\n")
                continuation.yield(.textDelta("```\n\(tailLines)\n```\n"))

                if attempt < maxAttempts - 1 {
                    if isCancelled() { return .failed }
                    continuation.yield(.textDelta("**Tests failed.** Sending to debugger...\n\n"))

                    let debugPrompt = """
                    Tests failed with the following output. Fix the issues so that tests pass without errors or warnings.

                    ```
                    \(output.suffix(50).joined(separator: "\n"))
                    ```

                    Fix all issues. The code must compile without warnings and all tests must pass.
                    """

                    let modifiedFiles = WorkspaceScanner.listUncommittedSourceFiles(
                        workspacePath: context.workspacePath,
                        excludedPaths: context.excludedPaths
                    )
                    let debugContext = modifiedFiles.isEmpty ? context : WorkspaceContext(
                        workspacePaths: context.workspacePaths,
                        isNamedWorkspace: context.isNamedWorkspace,
                        workspaceName: context.workspaceName,
                        excludedPaths: context.excludedPaths,
                        includedPaths: modifiedFiles,
                        openFiles: context.openFiles,
                        activeSelection: context.activeSelection,
                        activeFilePath: context.activeFilePath,
                        activeRootPath: context.activeRootPath
                    )

                    do {
                        let debugStream = try await executionProvider.send(
                            prompt: debugPrompt,
                            context: debugContext,
                            imageURLs: nil
                        )
                        for try await event in debugStream {
                            await waitWhilePaused()
                            if isCancelled() { break }
                            continuation.yield(event)
                        }
                    } catch {
                        continuation.yield(.textDelta("**Debug fix error:** \(error.localizedDescription)\n"))
                    }
                } else {
                    continuation.yield(.textDelta("**Tests still failing after \(maxAttempts) attempts.**\n"))
                }
            } catch {
                continuation.yield(.textDelta("**Unable to run tests:** \(error.localizedDescription)\n"))
                return .failed
            }
        }
        return .failed
    }

    static func hasTestFailureSignal(in lowercasedOutput: String) -> Bool {
        if lowercasedOutput.contains("test failed")
            || lowercasedOutput.contains("tests failed")
            || lowercasedOutput.contains("assertion failed")
            || lowercasedOutput.contains("xctassertion failed")
            || lowercasedOutput.contains("failures!")
            || lowercasedOutput.contains("test result: fail")
        {
            return true
        }

        let regexPatterns = [
            #"(?m)^\s*fail\s+\S+"#,
            #"(?m)^\s*tests:\s+.*\bfailed\b"#,
            #"(?m)^=+.*\b\d+\s+failed\b.*=+$"#,
            #"(?m)^\s*test result:\s*failed\b"#,
        ]
        return regexPatterns.contains {
            lowercasedOutput.range(of: $0, options: .regularExpression) != nil
        }
    }

    static func outputSignalsTestFailure(_ output: String) -> Bool {
        hasTestFailureSignal(in: output.lowercased())
    }
}
