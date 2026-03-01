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

        var errorDescription: String? {
            switch self {
            case .analysisTransportFailed(let reason):
                "Analysis stream failed: \(reason)"
            case .analysisReturnedNoData:
                "Analysis completed without text output."
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
        analysisProvider.isAuthenticated() && executionProvider.isAuthenticated()
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
            let task = Task {
                do {
                    execController?.beginScope(.review)
                    defer { execController?.endScope(.review) }
                    execController?.clearSwarmStopRequested()
                    execController?.clearSwarmPauseRequested()

                    let isCancelled: @Sendable () -> Bool = {
                        Task.isCancelled || execController?.swarmStopRequested == true
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
                        let (diffFiles, diffError) = Self.gitDiffFiles(ref: ref, workspacePath: workspacePath)
                        filesToReview = diffFiles
                        if filesToReview.isEmpty {
                            let reason = diffError ?? "No changed files found"
                            continuation.yield(.textDelta("\(reason) against `\(ref)`.\n"))
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
                    let analysisText = analysisOutput

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
                    var lastTestPassed = false

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
                            continuation.yield(.textDelta("Continuing with next review round...\n"))
                            testPassed = false
                        case .failed:
                            testPassed = false
                        }
                        lastTestPassed = testPassed

                        if isCancelled() { break reviewLoop }

                        // ── Phase 5: Re-Review ─────────────────────────────────
                        // Skip re-review on the final round — there's no subsequent
                        // fix phase to act on the findings.
                        guard reviewRound < config.maxReviewRounds else { break reviewLoop }

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

                    if isCancelled() {
                        continuation.yield(.textDelta("\n**Review cancelled.**\n"))
                    } else {
                        let testVerdict = lastTestPassed ? "Tests passing." : "Tests failing — manual intervention may be needed."
                        continuation.yield(.textDelta("\n---\n**Multi-swarm code review complete.** \(testVerdict)\n"))
                    }

                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
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
    ) async throws -> String {
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

        var textChunks: [String] = []
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
                    textChunks.append(delta)
                }
            }
        } catch {
            continuation.yield(.textDelta("\n**Analysis error:** \(error.localizedDescription)\n"))
            throw ReviewPipelineError.analysisTransportFailed(error.localizedDescription)
        }

        let fullText = textChunks.joined()
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ReviewPipelineError.analysisReturnedNoData
        }

        return trimmed
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

    /// Try to extract JSON review tasks from analysis text.
    /// Supports both fenced code blocks (```json ... ```) and bare JSON arrays.
    static func extractReviewTasksJSON(
        from text: String,
        allowedFiles: [String]? = nil
    ) -> ExtractedReviewTasks? {
        let allowedSet = allowedFiles.map(Set.init)

        // Strategy 1: Try markdown code block: ```json ... ```
        // Iterate matches from last to first — prefer the last valid task block,
        // but fall back to earlier matches if the last one fails to parse.
        let codeBlockPattern = #"```json\s*\n(\[[\s\S]*?\])\s*\n```"#
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            var lastInvalidReason: String?
            for match in matches.reversed() {
                guard let jsonRange = Range(match.range(at: 1), in: text) else { continue }
                let jsonStr = String(text[jsonRange])
                switch parseTasksJSON(jsonStr, allowedFiles: allowedSet) {
                case .tasks(let tasks):
                    return .jsonTasks(tasks)
                case .invalidJSON(let reason):
                    lastInvalidReason = lastInvalidReason ?? reason
                }
            }
            if let reason = lastInvalidReason {
                return .invalidJSON(reason: reason)
            }
        }

        // Strategy 2: Try bare JSON array (no fences) — some models omit code fences.
        // Search from the end of the text for the last JSON array.
        let bareArrayPattern = #"\[\s*\{[\s\S]*?\}\s*\]"#
        if let regex = try? NSRegularExpression(pattern: bareArrayPattern, options: []) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: text) else { continue }
                let jsonStr = String(text[range])
                switch parseTasksJSON(jsonStr, allowedFiles: allowedSet) {
                case .tasks(let tasks):
                    return .jsonTasks(tasks)
                case .invalidJSON:
                    continue // try earlier matches
                }
            }
        }

        return .none
    }

    enum ExtractedReviewTasks {
        case jsonTasks([ReviewTask])
        case invalidJSON(reason: String)
    }

    /// Result of parsing a JSON string into ReviewTask array
    enum ParsedTasksResult {
        case tasks([ReviewTask])
        case invalidJSON(reason: String)
    }

    /// Parse JSON string into ReviewTask array, filtering by allowed files.
    static func parseTasksJSON(
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
        var claimedFiles = Set<String>()
        for (index, dict) in arr.enumerated() {
            let id = (dict["id"] as? String) ?? "review-\(index)"
            let description = (dict["description"] as? String) ?? "Fix issues in assigned files"
            let rawFiles = (dict["files"] as? [String]) ?? []
            let filteredFiles = rawFiles.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !filteredFiles.isEmpty else { continue }
            let scopedFiles: [String]
            if let allowedFiles {
                scopedFiles = filteredFiles.filter { allowedFiles.contains($0) && !claimedFiles.contains($0) }
            } else {
                scopedFiles = filteredFiles.filter { !claimedFiles.contains($0) }
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
            claimedFiles.formUnion(scopedFiles)
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
                    if isCancelled() {
                        // Emit completed so the UI card doesn't stay stuck on "started"
                        continuation.yield(.raw(type: "agent", payload: [
                            "title": task.description,
                            "detail": "completed",
                            "swarm_id": task.id,
                            "group_id": "swarm-\(task.id)"
                        ]))
                        return (task.id, [])
                    }

                    let taskFiles = Set(task.files)
                    // Acquire file locks (with cancellation awareness)
                    let acquired = await fileLockCoordinator.acquireLock(
                        files: taskFiles, swarmId: task.id, isCancelled: isCancelled
                    )

                    guard acquired else {
                        // Emit failed so the UI card shows the correct status
                        continuation.yield(.raw(type: "agent", payload: [
                            "title": task.description,
                            "detail": "failed",
                            "status": "failed",
                            "swarm_id": task.id,
                            "group_id": "swarm-\(task.id)"
                        ]))
                        return (task.id, [.textDelta("\n**Worker \(task.id) skipped:** could not acquire file locks.\n")])
                    }

                    var collected: [StreamEvent] = []
                    var workerDidError = false

                    // Build scoped context for this worker.
                    // Pass task.files as includedPaths so the provider scopes tool
                    // access to the worker's assigned files, but the full workspace
                    // remains available via workspacePaths for read-only context.
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
                            await waitWhilePaused()
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
                        workerDidError = true
                        collected.append(.textDelta("\n**Worker \(task.id) error:** \(error.localizedDescription)\n"))
                    }

                    // Release locks synchronously within the task group (not fire-and-forget)
                    await fileLockCoordinator.releaseLock(files: taskFiles, swarmId: task.id)

                    // Emit correct lifecycle event: failed if worker errored, completed otherwise
                    let finalDetail = workerDidError ? "failed" : "completed"
                    var finalPayload: [String: String] = [
                        "title": task.description,
                        "detail": finalDetail,
                        "swarm_id": task.id,
                        "group_id": "swarm-\(task.id)"
                    ]
                    if workerDidError { finalPayload["status"] = "failed" }
                    continuation.yield(.raw(type: "agent", payload: finalPayload))

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

        var reReviewChunks: [String] = []
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
                    reReviewChunks.append(delta)
                }
            }
        } catch {
            let partialText = reReviewChunks.joined()
            continuation.yield(.textDelta("\n**Re-review error:** \(error.localizedDescription)\n"))
            return ReReviewOutcome(
                text: partialText,
                findings: .inconclusive(
                    reason: "Re-review stream failed: \(error.localizedDescription)"
                )
            )
        }

        let fullText = reReviewChunks.joined()
        let findings = findingsContainIssues(fullText)
        switch findings {
        case .issues:
            return ReReviewOutcome(text: fullText, findings: .issues)
        case .clean:
            return ReReviewOutcome(text: fullText, findings: .clean)
        case .inconclusive(let reason):
            return ReReviewOutcome(
                text: fullText,
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
        let ref = String(prompt[refRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRange = Range(match.range, in: prompt)!
        let clean = String(prompt[cleanRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean.isEmpty ? "Review all changes" : clean, ref)
    }

    /// Get files changed since a commit ref using git diff.
    /// Returns `(files, error)` — error is non-nil if git failed.
    static func gitDiffFiles(ref: String, workspacePath: URL) -> (files: [String], error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // Place ref BEFORE "--" so git treats it as a revision, not a pathspec.
        // The "--" separator prevents any subsequent path arguments from being
        // interpreted as flags, but the revision must precede it.
        process.arguments = ["diff", "--name-only", "--diff-filter=ACMR", ref, "--"]
        process.currentDirectoryURL = workspacePath
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        // Collect stderr asynchronously to prevent pipe buffer deadlock.
        // If both stdout and stderr produce large output, blocking on one
        // before the other can fill the pipe buffer and freeze the process.
        var errData = Data()
        let errLock = NSLock()
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            errLock.lock()
            errData.append(chunk)
            errLock.unlock()
        }

        do {
            try process.run()
        } catch {
            errPipe.fileHandleForReading.readabilityHandler = nil
            return ([], "Failed to run git diff: \(error.localizedDescription)")
        }

        // Read stdout BEFORE waitUntilExit to prevent pipe buffer deadlock
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        errPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            errLock.lock()
            let capturedErrData = errData
            errLock.unlock()
            let errMsg = String(data: capturedErrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
            return ([], "git diff failed for ref '\(ref)': \(errMsg)")
        }
        guard let output = String(data: data, encoding: .utf8) else {
            return ([], "Failed to decode git diff output as UTF-8.")
        }
        let sourceExtensions = Set([
            "swift", "ts", "tsx", "js", "jsx", "py", "go", "rs",
            "java", "kt", "kts", "rb", "php", "c", "cpp", "h", "hpp", "m", "mm",
            "cs", "scala", "dart", "lua", "sh", "bash", "zsh",
            "sql", "graphql", "gql", "proto", "r", "ex", "exs",
            "zig", "nim", "v", "svelte", "vue", "elm"
        ])
        let files = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { path in
                let ext = (path as NSString).pathExtension.lowercased()
                return sourceExtensions.contains(ext)
            }
        return (files, nil)
    }

    /// Check if findings text contains actionable issues.
    /// Uses word-boundary matching to avoid substring false positives
    /// (e.g. "dismissal" should not match "sql", "submission" should not match "permission").
    ///
    /// Priority order:
    /// 1. Check clean/no-issues phrases FIRST (most reliable, handles negated contexts like
    ///    "No critical issues found" which would otherwise false-positive on "critical").
    /// 2. Check inconclusive phrases.
    /// 3. Check strict multi-word issue indicators.
    /// 4. Check word-boundary single-word indicators last (weakest signal).
    private static func findingsContainIssues(_ text: String) -> ReviewFindingsState {
        let lower = text.lowercased()

        // ── 1. Check clean/no-issues phrases FIRST ──────────────────────
        // These are the most reliable signals because they're multi-word phrases
        // that explicitly negate issues. Must be checked before issue indicators
        // to prevent false positives like "No critical issues" matching "critical".
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
            "no security vulnerabilities",
            "no security issues",
            "no race conditions",
            "no memory leaks",
            "no regressions",
            "no regression risks",
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
            "no remaining issues"
        ]
        if noIssuesIndicators.contains(where: { lower.contains($0) }) {
            return .clean
        }

        // ── 2. Check inconclusive phrases ───────────────────────────────
        let inconclusiveIndicators = [
            "could not determine",
            "unable to assess",
            "insufficient context",
            "need more information",
            "cannot evaluate",
            "unclear"
        ]
        if inconclusiveIndicators.contains(where: { lower.contains($0) }) {
            return .inconclusive(reason: "Review text contained inconclusive language.")
        }

        // ── 3. Check strict multi-word issue indicators ─────────────────
        // These are strong signals that real issues exist. Checked after clean
        // phrases so "No critical issues found" is correctly handled.
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

        // ── 4. Word-boundary indicators (weakest signal) ────────────────
        let wordBoundaryIndicators = [
            "leak", "exception", "permission", "authorization", "authentication"
        ]
        if wordBoundaryIndicators.contains(where: { containsWord(lower, word: $0) }) {
            return .issues
        }

        let weakWordBoundaryIndicators = ["bug", "fix", "warning", "error", "issue", "severity"]
        if weakWordBoundaryIndicators.contains(where: { containsWord(lower, word: $0) }) {
            return .issues
        }

        return .inconclusive(reason: "No robust issue indicators found in re-review output.")
    }

    /// Pre-compiled word-boundary regex cache to avoid recompilation on every call.
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

    /// Matches a word with word-boundary awareness to prevent substring false positives.
    private static func containsWord(_ text: String, word: String) -> Bool {
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

    /// Run test suite and optionally retry with debugger.
    /// Passes `executionController` so the test process respects stop/pause signals.
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
                    executionController: execController,
                    scope: .review
                )

                let fullOutput = output.joined(separator: "\n")
                let lower = fullOutput.lowercased()
                // Cross-framework test failure detection:
                // Swift/XCTest, Jest/npm, pytest, JUnit, cargo, generic
                let hasTestFailures = lower.contains("test failed")
                    || lower.contains("tests failed")
                    || lower.contains("assertion failed")
                    || lower.contains("xctassertion failed")
                    || lower.contains("failures!")          // JUnit
                    || lower.contains("tests:") && lower.contains("failed") // Jest summary
                    || lower.contains("fail ")              // Jest/npm "FAIL src/..."
                    || lower.contains("failed!")            // pytest
                    || lower.contains("error:")             // Generic compiler/test errors
                    || lower.contains("test result: fail")  // cargo test
                let passed = (status == 0) && !hasTestFailures

                if passed {
                    continuation.yield(.textDelta("**Tests passed successfully.**\n"))
                    return .passed
                }

                // Tests failed — show summary
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

                    // Scope debug context to the files being reviewed, not the entire workspace.
                    // This prevents the debugger from making unintended changes outside review scope.
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
                            prompt: debugPrompt, context: debugContext, imageURLs: nil
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
