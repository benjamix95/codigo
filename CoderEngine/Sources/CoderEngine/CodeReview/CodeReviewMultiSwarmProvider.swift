import Foundation

public struct CodeReviewMultiSwarmDebugSnapshot: Sendable, Equatable {
    public let analysisProviderId: String
    public let executionProviderId: String
    public let analysisRuntime: ToolRuntimeDebugSnapshot?
    public let executionRuntime: ToolRuntimeDebugSnapshot?

    public init(
        analysisProviderId: String,
        executionProviderId: String,
        analysisRuntime: ToolRuntimeDebugSnapshot?,
        executionRuntime: ToolRuntimeDebugSnapshot?
    ) {
        self.analysisProviderId = analysisProviderId
        self.executionProviderId = executionProviderId
        self.analysisRuntime = analysisRuntime
        self.executionRuntime = executionRuntime
    }
}

/// Multi-swarm provider for Code Review: performs streaming analysis, dynamically spawns
/// parallel fix workers based on analysis findings, coordinates via file locks,
/// aggregates fixes, runs test → re-review loops.
public final class CodeReviewMultiSwarmProvider: LLMProvider, @unchecked Sendable {
    public let id = "code-review-multi-swarm"
    public let displayName = "Code Review Multi-Swarm"
    public var attachmentCapabilities: ProviderAttachmentCapabilities {
        analysisProvider.attachmentCapabilities
    }

    private let config: MultiSwarmReviewConfig
    private let analysisProvider: any LLMProvider
    private let executionProvider: any LLMProvider
    private let executionController: ExecutionController?
    private let fileLockCoordinator = FileLockCoordinator()

    private enum ReviewTaskExtractionResult: Sendable {
        case tasks([ReviewTask])
        case noFixes
        case invalidJSON(reason: String)
        case noPayload(reason: String)
    }

    private enum AnalysisPhaseResult: Sendable {
        case success(text: String)
        case noPayload(text: String, reason: String)
    }

    private enum ReviewFindingsState: Sendable {
        case issues
        case clean
        case inconclusive(reason: String)
    }

    private enum TestExecutionResult: Sendable {
        case passed
        case failed
        case inconclusive(reason: String)
    }

    private enum ReviewPipelineError: Error, LocalizedError {
        case analysisTransportFailed(String)
        case analysisReturnedNoData
        case taskPayloadMissing
        case taskPayloadInvalid(String)

        var errorDescription: String? {
            switch self {
            case .analysisTransportFailed(let reason):
                "Analysis stream failed: \(reason)"
            case .analysisReturnedNoData:
                "Analysis completed without text output."
            case .taskPayloadMissing:
                "No structured task payload found in analysis output."
            case .taskPayloadInvalid(let reason):
                "Invalid task payload in analysis output: \(reason)"
            }
        }
    }

    public init(
        config: MultiSwarmReviewConfig,
        analysisProvider: any LLMProvider,
        executionProvider: any LLMProvider,
        executionController: ExecutionController? = nil
    ) {
        self.config = config
        self.analysisProvider = analysisProvider
        self.executionProvider = executionProvider
        self.executionController = executionController
    }

    public func isAuthenticated() -> Bool {
        analysisProvider.isAuthenticated()
    }

    public func debugSnapshot() async -> CodeReviewMultiSwarmDebugSnapshot {
        let analysisRuntime = await (analysisProvider as? ToolEnabledLLMProvider)?
            .debugToolRuntimeSnapshot()
        let executionRuntime = await (executionProvider as? ToolEnabledLLMProvider)?
            .debugToolRuntimeSnapshot()
        return CodeReviewMultiSwarmDebugSnapshot(
            analysisProviderId: analysisProvider.id,
            executionProviderId: executionProvider.id,
            analysisRuntime: analysisRuntime,
            executionRuntime: executionRuntime
        )
    }

    // MARK: - Review Task (Dynamic)

    /// A task dynamically created by the analysis LLM
    struct ReviewTask: Sendable {
        let id: String           // "review-0", "review-1", ...
        let description: String  // what the worker should fix
        let files: [String]      // scoped file paths
        let severity: String     // "critical", "warning", "suggestion"
    }

    // MARK: - Main Pipeline

    public func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]? = nil
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let config = self.config
        let analysisProvider = self.analysisProvider
        let executionProvider = self.executionProvider
        let execController = self.executionController
        let fileLockCoordinator = self.fileLockCoordinator

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    execController?.beginScope(.review)
                    defer { execController?.clearCurrentProcess() }
                    execController?.clearSwarmStopRequested()
                    execController?.clearSwarmPauseRequested()

                    let isCancelled: @Sendable () -> Bool = {
                        execController?.swarmStopRequested == true
                    }

                    let waitWhilePaused: @Sendable () async -> Void = {
                        while execController?.swarmPauseRequested == true {
                            if isCancelled() { break }
                            try? await Task.sleep(nanoseconds: 120_000_000)
                        }
                    }

                    // Parse optional against-commit ref from prompt prefix: [AGAINST:ref]
                    let (cleanPrompt, againstRef) = Self.parseAgainstRef(from: prompt)
                    let workspacePath = context.workspacePath

                    // ── Resolve files to review ────────────────────────────────
                    continuation.yield(.started)

                    let filesToReview: [String]
                    if let ref = againstRef {
                        filesToReview = Self.gitDiffFiles(ref: ref, workspacePath: workspacePath)
                        if filesToReview.isEmpty {
                            continuation.yield(.textDelta("No changed files found against `\(ref)`.\n"))
                            continuation.yield(.completed)
                            continuation.finish()
                            return
                        }
                    } else {
                        filesToReview = Self.resolveFiles(context: context)
                        if filesToReview.isEmpty {
                            continuation.yield(.textDelta("No uncommitted source files found. Nothing to review.\n"))
                            continuation.yield(.completed)
                            continuation.finish()
                            return
                        }
                    }

                    // ── Phase 1: Streaming Analysis ─────────────────────────
                    let analysisOutput = try await Self.runAnalysisPhase(
                        cleanPrompt: cleanPrompt,
                        againstRef: againstRef,
                        filesToReview,
                        config.maxWorkers,
                        context: context,
                        analysisProvider: analysisProvider,
                        continuation: continuation,
                        isCancelled: isCancelled,
                        waitWhilePaused: waitWhilePaused
                    )
                    let analysisText: String
                    switch analysisOutput {
                    case .success(let text):
                        analysisText = text
                    case .noPayload(let text, let reason):
                        // Analysis completed but no structured JSON found — treat as analysis-only result
                        continuation.yield(.textDelta("\n---\n**Analysis complete.** \(reason) No fix tasks generated.\n"))
                        analysisText = text
                    }

                    if isCancelled() {
                        continuation.yield(.textDelta("\n**Review cancelled.**\n"))
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }

                    // ── Phase 2: Dynamic Task Creation ─────────────────────────
                    let taskExtraction = Self.parseReviewTasks(
                        from: analysisText,
                        filesToReview: filesToReview,
                        maxWorkers: config.maxWorkers
                    )

                    let tasks: [ReviewTask]
                    switch taskExtraction {
                    case .noFixes, .noPayload:
                        tasks = []
                    case .tasks(let parsedTasks):
                        tasks = parsedTasks
                    case .invalidJSON(let reason):
                        continuation.yield(.textDelta("\n**Warning:** Could not parse task JSON: \(reason). Treating as analysis-only.\n"))
                        tasks = []
                    }

                    // Emit worker plan for UI
                    for task in tasks {
                        continuation.yield(.raw(type: "review-worker-plan", payload: [
                            "worker_id": task.id,
                            "description": task.description,
                            "severity": task.severity,
                            "fileCount": "\(task.files.count)",
                            "files": task.files.prefix(5).joined(separator: ", ")
                                + (task.files.count > 5 ? " (+\(task.files.count - 5) more)" : "")
                        ]))
                    }

                    // ── Analysis-only mode stops here ───────────────────────────
                    if config.enabledPhases == .analysisOnly {
                        continuation.yield(.textDelta("\n---\n**Analysis complete.** (Analysis-only mode)\n"))
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }

                    // ── No actionable tasks -> run tests only ────────────────────
                    if tasks.isEmpty {
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
                        case .passed:
                            "No issues found, tests pass."
                        case .failed:
                            "Tests have issues."
                        case .inconclusive(let reason):
                            "Tests status inconclusive: \(reason)"
                        }
                        continuation.yield(.textDelta("\n---\n**Review complete.** \(verdict)\n"))
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }

                    continuation.yield(.textDelta("\n**Workers planned:** \(tasks.count) (max \(config.maxWorkers))\n\n"))

                    // ── Phase 3–5: Fix → Test → Re-Review Loop ─────────────────
                    var reviewRound = 0
                    var currentTasks = tasks

                    reviewLoop: while reviewRound < config.maxReviewRounds {
                        if isCancelled() { break reviewLoop }
                        await waitWhilePaused()
                        reviewRound += 1

                        continuation.yield(.raw(type: "review-fix-round", payload: [
                            "round": "\(reviewRound)",
                            "maxRounds": "\(config.maxReviewRounds)"
                        ]))

                        // ── Phase 3: Parallel Fix ──────────────────────────────
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

                        // ── Phase 4: Test ──────────────────────────────────────
                        continuation.yield(.textDelta("\n### Test Phase\n\n"))

                        let testResult = await Self.runTests(
                            context: context,
                            executionProvider: executionProvider,
                            continuation: continuation,
                            execController: execController,
                            isCancelled: isCancelled,
                            waitWhilePaused: waitWhilePaused
                        )

                        let testPassed: Bool
                        switch testResult {
                        case .passed:
                            testPassed = true
                        case .inconclusive(let reason):
                            continuation.yield(.textDelta("\n**Review validation incomplete:** \(reason)\n"))
                            continuation.yield(.textDelta("\n---\n**Review complete (inconclusive).**\n"))
                            continuation.yield(.completed)
                            continuation.finish()
                            return
                        case .failed:
                            testPassed = false
                        }

                        if isCancelled() { break reviewLoop }

                        // ── Phase 5: Re-Review ─────────────────────────────────
                        if reviewRound < config.maxReviewRounds {
                            continuation.yield(.textDelta("\n### Re-Review Phase (Round \(reviewRound))\n\n"))

                            let modifiedFiles = WorkspaceScanner.listUncommittedSourceFiles(
                                workspacePath: workspacePath,
                                excludedPaths: context.excludedPaths
                            )

                            if modifiedFiles.isEmpty {
                                continuation.yield(.textDelta("No modified files remain. Review complete.\n"))
                                break reviewLoop
                            }

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

                            // If re-review found no issues or is inconclusive, stop the loop
                            switch reReviewOutcome.findings {
                            case .clean:
                                continuation.yield(.textDelta("\n**All clear.** No new issues found.\n"))
                                break reviewLoop
                            case .inconclusive(let reason):
                                continuation.yield(.textDelta(
                                    "\n**Re-review inconclusive:** \(reason). Review stopped to avoid unsafe fallback.\n"
                                ))
                                break reviewLoop
                            case .issues:
                                break // continue processing below
                            }

                            // Parse new dynamic tasks for next round
                            let nextRoundTasks = Self.parseReviewTasks(
                                from: reReviewOutcome.text,
                                filesToReview: modifiedFiles,
                                maxWorkers: config.maxWorkers
                            )

                            switch nextRoundTasks {
                            case .tasks(let newTasks) where !newTasks.isEmpty:
                                currentTasks = newTasks
                            case .tasks, .noFixes:
                                continuation.yield(.textDelta("\n**All clear.** No actionable fix tasks for next round.\n"))
                                break reviewLoop
                            case .noPayload:
                                continuation.yield(.textDelta(
                                    "\n**Re-review payload missing.** Unable to safely continue without validated tasks.\n"
                                ))
                                continuation.yield(.textDelta("\n---\n**Review complete (inconclusive).**\n"))
                                continuation.yield(.completed)
                                continuation.finish()
                                return
                            case .invalidJSON(let reason):
                                continuation.yield(.textDelta(
                                    "\n**Re-review payload invalid: \(reason)** Stopping for safety.\n"
                                ))
                                continuation.yield(.textDelta("\n---\n**Review complete (inconclusive).**\n"))
                                continuation.yield(.completed)
                                continuation.finish()
                                return
                            }

                            continuation.yield(.textDelta(
                                "\n**New issues found.** Proceeding to fix round \(reviewRound + 1) with \(currentTasks.count) worker(s)...\(testPassed ? " (tests pass but code issues remain)" : "")\n"
                            ))
                        }
                    }

                    if isCancelled() {
                        continuation.yield(.textDelta("\n**Review cancelled.**\n"))
                    } else {
                        continuation.yield(.textDelta("\n---\n**Multi-swarm code review complete.**\n"))
                    }

                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Phase 1: Streaming Analysis

    /// Streams ALL events from analysis to the continuation (identical to agent mode).
    /// Returns the collected full analysis text.
    private static func runAnalysisPhase(
        cleanPrompt: String,
        againstRef: String?,
        _ filesToReview: [String],
        _ maxWorkers: Int,
        context: WorkspaceContext,
        analysisProvider: any LLMProvider,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        isCancelled: @Sendable @escaping () -> Bool,
        waitWhilePaused: @Sendable @escaping () async -> Void
    ) async throws -> AnalysisPhaseResult {
        let fileList = filesToReview.joined(separator: "\n")
        let scopeDesc = againstRef.map { "Changes against `\($0)`" } ?? "Uncommitted changes"

        let analysisPrompt = """
        You are a senior code reviewer performing a thorough analysis.

        ## Scope
        \(scopeDesc) — \(filesToReview.count) files:
        \(fileList)

        ## User Instructions
        \(cleanPrompt.isEmpty ? "Review the code thoroughly." : cleanPrompt)

        ## Review Criteria
        1. **Bugs** — logic errors, null/nil dereferences, race conditions, off-by-one
        2. **Security** — injection, hardcoded secrets, insecure patterns
        3. **Performance** — unnecessary allocations, N+1 queries, blocking calls
        4. **Style** — naming, dead code, overly complex logic
        5. **Architecture** — SOLID violations, tight coupling, missing error handling

        ## Output Format
        First, provide your detailed analysis with findings.

        Then, at the very end of your response, output a JSON block wrapped in ```json fences.
        This JSON is an array of fix tasks for parallel workers. Each task groups related files:

        ```json
        [
          {
            "id": "review-0",
            "description": "Brief description of what to fix",
            "files": ["path/to/file1.swift", "path/to/file2.swift"],
            "severity": "critical"
          }
        ]
        ```

        Rules for tasks:
        - Group related fixes into the same task (same area/module)
        - Each file should appear in at most ONE task
        - severity: "critical", "warning", or "suggestion"
        - If no fixes are needed, output an empty array: ```json\n[]\n```
        - Maximum \(maxWorkers) tasks — group smaller fixes together
        """

        var fullText = ""
        do {
            let stream = try await analysisProvider.send(
                prompt: analysisPrompt,
                context: context,
                imageURLs: nil
            )
            for try await event in stream {
                await waitWhilePaused()
                if isCancelled() { break }
                // Pass ALL events through to the continuation (identical to agent mode)
                continuation.yield(event)
                if case .textDelta(let delta) = event {
                    fullText += delta
                }
            }
        } catch {
            continuation.yield(.textDelta("\n**Analysis error:** \(error.localizedDescription)\n"))
            throw ReviewPipelineError.analysisTransportFailed(error.localizedDescription)
        }

        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ReviewPipelineError.analysisReturnedNoData
        }

        let extraction = extractReviewTasksJSON(from: trimmed)
        switch extraction {
        case .jsonTasks:
            return .success(text: trimmed)
        case .invalidJSON(let reason):
            return .noPayload(text: trimmed, reason: reason)
        case .none:
            return .noPayload(text: trimmed, reason: "No structured task JSON block found.")
        }
    }

    // MARK: - Phase 2: Parse Review Tasks

    /// Extracts structured tasks from analysis output.
    private static func parseReviewTasks(
        from analysisText: String,
        filesToReview: [String],
        maxWorkers: Int
    ) -> ReviewTaskExtractionResult {
        // Try to extract JSON tasks from the analysis
        guard let extraction = extractReviewTasksJSON(from: analysisText, allowedFiles: filesToReview) else {
            return .noPayload(
                reason: "No JSON review task block found in analysis output."
            )
        }

        switch extraction {
        case .jsonTasks(let tasks) where tasks.isEmpty:
            return .noFixes
        case .jsonTasks(let tasks):
            return .tasks(Array(tasks.prefix(maxWorkers)))
        case .invalidJSON(let reason):
            return .invalidJSON(reason: reason)
        }
    }

    /// Try to extract JSON review tasks from analysis text
    private static func extractReviewTasksJSON(
        from text: String,
        allowedFiles: [String]? = nil
    ) -> ExtractedReviewTasks? {
        let allowedSet = allowedFiles.map(Set.init)
        // Try markdown code block: ```json ... ``` — take the LAST match (the real task block, not examples)
        let codeBlockPattern = #"```json\s*\n(\[[\s\S]*?\])\s*\n```"#
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            // Use the last match — LLMs often include example blocks before the real one
            if let match = matches.last,
               let jsonRange = Range(match.range(at: 1), in: text) {
                let jsonStr = String(text[jsonRange])
                switch parseTasksJSON(jsonStr, allowedFiles: allowedSet) {
                case .tasks(let tasks):
                    return .jsonTasks(tasks)
                case .invalidJSON(let reason):
                    return .invalidJSON(reason: reason)
                }
            }
        }

        return .none
    }

    private enum ExtractedReviewTasks {
        case jsonTasks([ReviewTask])
        case invalidJSON(reason: String)
    }

    /// Parse JSON string into ReviewTask array
    private enum ParsedTasksResult {
        case tasks([ReviewTask])
        case invalidJSON(reason: String)
    }

    /// Parse JSON string into ReviewTask array
    private static func parseTasksJSON(
        _ jsonStr: String,
        allowedFiles: Set<String>?
    ) -> ParsedTasksResult {
        guard let data = jsonStr.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return .invalidJSON(reason: "Unable to parse task JSON block as an array.")
        }

        var tasks: [ReviewTask] = []
        var invalidEntries = 0
        for (index, dict) in arr.enumerated() {
            let id = (dict["id"] as? String) ?? "review-\(index)"
            let description = (dict["description"] as? String) ?? "Fix issues in assigned files"
            let rawFiles = (dict["files"] as? [String]) ?? []
            let filteredFiles = rawFiles.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !filteredFiles.isEmpty else { continue }
            let scopedFiles: [String]
            if let allowedFiles {
                scopedFiles = filteredFiles.filter { allowedFiles.contains($0) }
            } else {
                scopedFiles = filteredFiles
            }
            guard !scopedFiles.isEmpty else {
                invalidEntries += 1
                continue
            }
            let normalizedDescription = description.isEmpty
                ? "Fix issues in assigned files"
                : description
            let severityRaw = (dict["severity"] as? String)?.lowercased() ?? "warning"
            let allowedSeverities: Set<String> = ["critical", "warning", "suggestion"]
            let severity = allowedSeverities.contains(severityRaw) ? severityRaw : "warning"
            tasks.append(
                ReviewTask(
                    id: id,
                    description: normalizedDescription,
                    files: scopedFiles,
                    severity: severity
                )
            )
        }
        if tasks.isEmpty && !arr.isEmpty {
            return .invalidJSON(
                reason: invalidEntries > 0
                    ? "All task entries were invalid or outside review scope." : "Unable to parse task array entries." )
        }
        return .tasks(tasks)
    }

    // MARK: - Phase 3: Parallel Fix

    /// Runs fix workers in parallel with file-lock coordination.
    /// Card lifecycle events (started/completed) are emitted immediately for live UI.
    /// Text output is serialized: collected per-worker then emitted sequentially for linear chat.
    private static func runParallelFixPhase(
        tasks: [ReviewTask],
        context: WorkspaceContext,
        executionProvider: any LLMProvider,
        fileLockCoordinator: FileLockCoordinator,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        isCancelled: @Sendable @escaping () -> Bool,
        waitWhilePaused: @Sendable @escaping () async -> Void
    ) async {
        guard !tasks.isEmpty else { return }

        continuation.yield(.textDelta("Launching \(tasks.count) parallel worker(s)...\n\n"))

        // Emit ALL worker started events immediately so cards appear in the chat at once
        for task in tasks {
            continuation.yield(.raw(type: "agent", payload: [
                "title": task.description,
                "detail": "started",
                "swarm_id": task.id,
                "group_id": "swarm-\(task.id)"
            ]))
        }

        // Run workers in parallel, collect their text events
        let workerResults: [(taskId: String, events: [StreamEvent])] = await withTaskGroup(
            of: (String, [StreamEvent]).self,
            returning: [(String, [StreamEvent])].self
        ) { group in
            for task in tasks {
                group.addTask {
                    if isCancelled() { return (task.id, []) }

                    // Acquire file locks (with cancellation awareness)
                    await fileLockCoordinator.acquireLock(
                        files: Set(task.files), swarmId: task.id, isCancelled: isCancelled
                    )

                    var collected: [StreamEvent] = []

                    // Build scoped context for this worker
                    let scopedContext = WorkspaceContext(
                        workspacePaths: context.workspacePaths,
                        isNamedWorkspace: context.isNamedWorkspace,
                        workspaceName: context.workspaceName,
                        excludedPaths: context.excludedPaths,
                        includedPaths: task.files,
                        openFiles: context.openFiles,
                        activeSelection: context.activeSelection,
                        activeFilePath: context.activeFilePath,
                        activeRootPath: context.activeRootPath
                    )

                    let fixPrompt = """
                    You are a code fixer. Apply targeted fixes to the following files.

                    ## Task
                    \(task.description)

                    ## Severity
                    \(task.severity)

                    ## Files in Scope
                    \(task.files.joined(separator: "\n"))

                    ## Instructions
                    - Fix all issues identified for these files
                    - Make minimal, targeted changes — do not refactor beyond what is needed
                    - Preserve existing code style and conventions
                    - Do NOT modify files outside your scope
                    """

                    do {
                        let stream = try await executionProvider.send(
                            prompt: fixPrompt,
                            context: scopedContext,
                            imageURLs: nil
                        )
                        for try await event in stream {
                            if isCancelled() { break }
                            // Enrich raw events with swarm_id for SwarmLiveReducer routing
                            switch event {
                            case .raw(let type, var payload):
                                payload["swarm_id"] = task.id
                                payload["group_id"] = "swarm-\(task.id)"
                                // Emit raw events immediately so card activity updates live
                                continuation.yield(.raw(type: type, payload: payload))
                            default:
                                collected.append(event)
                            }
                        }
                    } catch {
                        collected.append(.textDelta("\n**Worker \(task.id) error:** \(error.localizedDescription)\n"))
                    }

                    // Emit completed event immediately for live card status
                    continuation.yield(.raw(type: "agent", payload: [
                        "title": task.description,
                        "detail": "completed",
                        "swarm_id": task.id,
                        "group_id": "swarm-\(task.id)"
                    ]))

                    // Release file locks
                    await fileLockCoordinator.releaseLock(
                        files: Set(task.files), swarmId: task.id
                    )

                    return (task.id, collected)
                }
            }

            var results: [(String, [StreamEvent])] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        // Serialize text output: emit collected text events one worker at a time for linear chat
        let sorted = workerResults.sorted { $0.taskId < $1.taskId }
        for (taskId, events) in sorted {
            await waitWhilePaused()
            if isCancelled() { break }
            continuation.yield(.textDelta("\n#### Worker \(taskId)\n\n"))
            for event in events {
                continuation.yield(event)
            }
        }
    }

    // MARK: - Phase 5: Re-Review

    private struct ReReviewOutcome {
        let text: String
        let hasNewIssues: Bool
        let findings: ReviewFindingsState
    }

    /// Streams re-review analysis and returns outcome details.
    private static func runReReviewPhase(
        modifiedFiles: [String],
        round: Int,
        context: WorkspaceContext,
        analysisProvider: any LLMProvider,
        maxWorkers: Int,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        isCancelled: @Sendable @escaping () -> Bool,
        waitWhilePaused: @Sendable @escaping () async -> Void
    ) async -> ReReviewOutcome {
        let reReviewContext = WorkspaceContext(
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

        let reReviewPrompt = """
        You are a code reviewer performing re-review round \(round).

        ## Files to Re-Review
        \(modifiedFiles.joined(separator: "\n"))

        ## Instructions
        These files were modified by a previous fix phase. Check:
        1. Were the original issues properly fixed?
        2. Did the fixes introduce any new bugs or regressions?
        3. Is the code clean and well-structured after the fixes?

        If everything looks good, respond with: "No issues found."

        Otherwise, list remaining issues and at the end output a JSON task block:
        ```json
        [
          {
            "id": "review-0",
            "description": "Brief description of what to fix",
            "files": ["path/to/file.swift"],
            "severity": "critical"
          }
        ]
        ```
        Maximum \(maxWorkers) tasks. Group related fixes together.
        """

        var fullText = ""
        do {
            let stream = try await analysisProvider.send(
                prompt: reReviewPrompt,
                context: reReviewContext,
                imageURLs: nil
            )
            for try await event in stream {
                await waitWhilePaused()
                if isCancelled() { break }
                // Pass through to continuation (streaming re-review identical to agent mode)
                continuation.yield(event)
                if case .textDelta(let delta) = event {
                    fullText += delta
                }
            }
        } catch {
            continuation.yield(.textDelta("\n**Re-review error:** \(error.localizedDescription)\n"))
            return ReReviewOutcome(
                text: fullText,
                hasNewIssues: true,
                findings: .inconclusive(
                    reason: "Re-review stream failed: \(error.localizedDescription)"
                )
            )
        }

        let findings = findingsContainIssues(fullText)
        switch findings {
        case .issues:
            return ReReviewOutcome(text: fullText, hasNewIssues: true, findings: .issues)
        case .clean:
            return ReReviewOutcome(text: fullText, hasNewIssues: false, findings: .clean)
        case .inconclusive(let reason):
            return ReReviewOutcome(
                text: fullText,
                hasNewIssues: false,
                findings: .inconclusive(reason: reason)
            )
        }
    }

    // MARK: - Helpers

    /// Resolve files to review from context
    static func resolveFiles(context: WorkspaceContext) -> [String] {
        WorkspaceScanner.listUncommittedSourceFiles(
            workspacePath: context.workspacePath,
            excludedPaths: context.excludedPaths
        )
    }

    /// Parse [AGAINST:ref] prefix from prompt
    static func parseAgainstRef(from prompt: String) -> (cleanPrompt: String, ref: String?) {
        let pattern = #"^\[AGAINST:([^\]]+)\]\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
              let refRange = Range(match.range(at: 1), in: prompt)
        else {
            return (prompt, nil)
        }
        let ref = String(prompt[refRange])
        let cleanRange = Range(match.range, in: prompt)!
        let clean = String(prompt[cleanRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean.isEmpty ? "Review all changes" : clean, ref)
    }

    /// Get files changed since a commit ref using git diff
    static func gitDiffFiles(ref: String, workspacePath: URL) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "--name-only", "--diff-filter=ACMR", ref]
        process.currentDirectoryURL = workspacePath
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        let sourceExtensions = Set([
            "swift", "ts", "tsx", "js", "jsx", "py", "go", "rs",
            "java", "kt", "rb", "php", "c", "cpp", "h", "hpp", "m", "mm"
        ])
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { path in
                let ext = (path as NSString).pathExtension.lowercased()
                return sourceExtensions.contains(ext)
            }
    }

    /// Check if findings text contains actionable issues.
    /// Uses word-boundary matching to avoid substring false positives
    /// (e.g. "dismissal" should not match "sql", "submission" should not match "permission").
    private static func findingsContainIssues(_ text: String) -> ReviewFindingsState {
        let lower = text.lowercased()

        let noIssuesIndicators = [
            "no issues found",
            "all clear",
            "looks good",
            "no problems",
            "nothing to fix",
            "no changes required",
            "nothing else to change"
        ]
        if noIssuesIndicators.contains(where: { lower.contains($0) }) && text.count < 2_000 {
            return .clean
        }

        let inconclusiveIndicators = [
            "unable to determine",
            "cannot determine",
            "insufficient context",
            "inconclusive",
            "i couldn't",
            "i am unable",
            "not enough information"
        ]
        if inconclusiveIndicators.contains(where: { lower.contains($0) }) {
            return .inconclusive(reason: "Re-review output did not reach a confident conclusion.")
        }

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
            "use-after-free"
        ]
        if strictIssueIndicators.contains(where: { lower.contains($0) }) {
            return .issues
        }

        let wordBoundaryIndicators = [
            "leak", "exception", "permission", "authorization", "authentication"
        ]
        if wordBoundaryIndicators.contains(where: { containsWord(lower, word: $0) }) {
            return .issues
        }

        if lower.count < 150 {
            return .clean
        }

        let weakWordBoundaryIndicators = ["bug", "fix", "warning", "error", "issue", "severity"]
        if weakWordBoundaryIndicators.contains(where: { containsWord(lower, word: $0) }) {
            return .issues
        }

        return .inconclusive(reason: "No robust issue indicators found in re-review output.")
    }

    /// Matches a word with word-boundary awareness to prevent substring false positives.
    private static func containsWord(_ text: String, word: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text.contains(word)
        }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Run test suite and optionally retry with debugger
    private static func runTests(
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

            continuation.yield(.textDelta("Running tests\(attempt > 0 ? " (retry \(attempt + 1))" : "")...\n"))

            do {
                let (output, status) = try await ProcessRunner.runCollecting(
                    executable: cmd.executable,
                    arguments: cmd.arguments,
                    workingDirectory: context.workspacePath,
                    scope: .review
                )

                let fullOutput = output.joined(separator: "\n")
                let lower = fullOutput.lowercased()
                let hasTestFailures = lower.contains("test failed")
                    || lower.contains("tests failed")
                    || lower.contains("failing")
                    || lower.contains("assertion failed")
                    || lower.contains("xctassert")
                let passed = (status == 0) && !hasTestFailures

                if passed {
                    continuation.yield(.textDelta("**Tests passed successfully.**\n"))
                    return .passed
                }

                // Tests failed — show summary
                let tailLines = output.suffix(20).joined(separator: "\n")
                continuation.yield(.textDelta("```\n\(tailLines)\n```\n"))

                if attempt < maxAttempts - 1 {
                    continuation.yield(.textDelta("**Tests failed.** Sending to debugger...\n\n"))

                    let debugPrompt = """
                    Tests failed with the following output. Fix the issues so that tests pass without errors or warnings.

                    ```
                    \(output.suffix(50).joined(separator: "\n"))
                    ```

                    Fix all issues. The code must compile without warnings and all tests must pass.
                    """

                    do {
                        let debugStream = try await executionProvider.send(
                            prompt: debugPrompt, context: context, imageURLs: nil
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
}
