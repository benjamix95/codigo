import Foundation

extension CodeReviewMultiSwarmProvider {
    static func findingsContainIssues(_ text: String) -> ReviewFindingsState {
        let lower = text.lowercased()

        let noIssuesIndicators = [
            "no issues found",
            "no issues were found",
            "no significant issues",
            "no problems found",
            "no bugs found",
            "no errors found",
            "no errors detected",
            "no errors",
            "no warnings found",
            "no warnings detected",
            "no warnings",
            "no fix needed",
            "no fixes needed",
            "no fix required",
            "no fixes required",
            "no critical issues",
            "no critical bugs",
            "no critical problems",
            "no critical findings",
            "no security vulnerabilities",
            "no security issues",
            "no security risks",
            "no security concerns",
            "no race conditions",
            "no race condition issues",
            "no memory leaks",
            "no regressions",
            "no regression risks",
            "no crashes",
            "no deadlocks",
            "no injection vulnerabilities",
            "no data loss risks",
            "no infinite loops",
            "code is clean",
            "code looks good",
            "looks good overall",
            "no major issues",
            "all checks pass",
            "all tests pass",
            "no vulnerabilities found",
            "no vulnerabilities detected",
            "lgtm",
            "everything looks good",
            "no actionable issues",
            "no remaining issues",
            "error handling is properly implemented",
            "error handling looks correct",
            "error handling is correct",
            "error handling is adequate",
            "error handling is good",
            "no error handling issues"
        ]
        let hasCleanIndicator = noIssuesIndicators.contains(where: { lower.contains($0) })
        // Sort indicators by length (longest first) so that longer phrases like
        // "no race condition issues" are stripped before shorter ones like "no race conditions",
        // preventing partial matches that leave issue-indicating fragments behind.
        let sortedIndicators = noIssuesIndicators.sorted { $0.count > $1.count }
        let issueScanText = sortedIndicators.reduce(lower) { partial, phrase in
            partial.replacingOccurrences(of: phrase, with: " ")
        }

        let inconclusiveIndicators = [
            "could not determine",
            "unable to assess",
            "insufficient context",
            "need more information",
            "cannot evaluate",
            "unclear"
        ]
        // Use word-boundary matching to avoid false positives (e.g. "nuclear" matching "unclear")
        let hasInconclusiveIndicator = inconclusiveIndicators.contains(where: { containsWord(lower, word: $0) })

        let strictIssueIndicators = [
            "critical",
            "high severity",
            "security vulnerability",
            "security risk",
            "security issue",
            "regression",
            "crash",
            "null pointer",
            "race condition",
            "memory leak",
            "command injection",
            "sql injection",
            "data loss",
            "deadlock",
            "infinite loop",
            "off-by-one",
            "null dereference",
            "segmentation fault",
            "thread-safety",
            "use-after-free",
            "buffer overflow",
            "integer overflow",
            "integer underflow",
            "path traversal",
            "cross-site scripting",
            "xss",
            "denial of service",
            "type confusion",
            "uninitialized variable",
            "uninitialized memory"
        ]
        let hasStrictIssueIndicator = strictIssueIndicators.contains(where: { issueScanText.contains($0) })

        let wordBoundaryIndicators = ["leak", "exception", "permission", "authorization", "authentication"]
        let hasWordBoundaryIssueIndicator = wordBoundaryIndicators.contains { containsWord(issueScanText, word: $0) }

        let weakWordBoundaryIndicators = ["bug", "fix", "warning", "error", "issue", "severity"]
        let hasWeakWordBoundaryIssueIndicator = weakWordBoundaryIndicators.contains { containsWord(issueScanText, word: $0) }

        if hasStrictIssueIndicator || hasWordBoundaryIssueIndicator || hasWeakWordBoundaryIssueIndicator {
            return .issues
        }

        if hasCleanIndicator {
            return .clean
        }

        if hasInconclusiveIndicator {
            return .inconclusive(reason: "Review text contained inconclusive language.")
        }

        return .inconclusive(reason: "No robust issue indicators found in re-review output.")
    }

    static func findingsStateDebugLabel(for text: String) -> String {
        switch findingsContainIssues(text) {
        case .issues: return "issues"
        case .clean: return "clean"
        case .inconclusive: return "inconclusive"
        }
    }

    private static let wordRegexCache: [String: NSRegularExpression] = {
        let words = ["leak", "exception", "permission", "authorization", "authentication",
                     "bug", "fix", "warning", "error", "issue", "severity"]
        var cache: [String: NSRegularExpression] = [:]
        for word in words {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                cache[word] = regex
            }
        }
        return cache
    }()

    static func containsWord(_ text: String, word: String) -> Bool {
        let regex: NSRegularExpression
        if let cached = wordRegexCache[word] {
            regex = cached
        } else {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
            guard let compiled = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return text.contains(word)
            }
            regex = compiled
        }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func sortedWorkerTaskIDsForDisplay(_ ids: [String]) -> [String] {
        ids.sorted(by: sortWorkerTaskIDForDisplay(_:_:))
    }

    static func sortWorkerTaskIDForDisplay(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
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

    private static func hasTestFailureSignal(in lowercasedOutput: String) -> Bool {
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
        for pattern in regexPatterns {
            if lowercasedOutput.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    static func outputSignalsTestFailure(_ output: String) -> Bool {
        hasTestFailureSignal(in: output.lowercased())
    }
}
