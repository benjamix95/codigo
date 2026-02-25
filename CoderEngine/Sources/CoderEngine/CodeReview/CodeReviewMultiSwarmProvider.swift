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

                    // ── Phase 1: Streaming Analysis (identical to agent mode) ──
                    let analysisText = await Self.runAnalysisPhase(
                        cleanPrompt: cleanPrompt,
                        againstRef: againstRef,
                        filesToReview: filesToReview,
                        maxWorkers: config.maxWorkers,
                        context: context,
                        analysisProvider: analysisProvider,
                        continuation: continuation,
                        isCancelled: isCancelled,
                        waitWhilePaused: waitWhilePaused
                    )

                    if isCancelled() {
                        continuation.yield(.textDelta("\n**Review cancelled.**\n"))
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }

                    // ── Phase 2: Dynamic Task Creation ─────────────────────────
                    let tasks = Self.parseReviewTasks(
                        from: analysisText,
                        filesToReview: filesToReview,
                        maxWorkers: config.maxWorkers
                    )

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

                    // ── No actionable tasks → run tests only ────────────────────
                    if tasks.isEmpty {
                        continuation.yield(.textDelta("\n**No actionable fix tasks.** Running tests...\n"))
                        let testPassed = await Self.runTests(
                            context: context,
                            executionProvider: executionProvider,
                            continuation: continuation,
                            execController: execController,
                            isCancelled: isCancelled,
                            waitWhilePaused: waitWhilePaused
                        )
                        let verdict = testPassed ? "No issues found, tests pass." : "Tests have issues."
                        continuation.yield(.textDelta("\n---\n**Review complete.** \(verdict)\n"))
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }

                    continuation.yield(.textDelta("\n**Workers planned:** \(tasks.count) (max \(config.maxWorkers))\n\n"))

                    // ── Phase 3–5: Fix → Test → Re-Review Loop ─────────────────
                    var reviewRound = 0
                    var currentTasks = tasks

                    while reviewRound < config.maxReviewRounds {
                        if isCancelled() { break }
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

                        if isCancelled() { break }

                        // ── Phase 4: Test ──────────────────────────────────────
                        continuation.yield(.textDelta("\n### Test Phase\n\n"))

                        let testPassed = await Self.runTests(
                            context: context,
                            executionProvider: executionProvider,
                            continuation: continuation,
                            execController: execController,
                            isCancelled: isCancelled,
                            waitWhilePaused: waitWhilePaused
                        )

                        if isCancelled() { break }

                        // ── Phase 5: Re-Review ─────────────────────────────────
                        if reviewRound < config.maxReviewRounds {
                            continuation.yield(.textDelta("\n### Re-Review Phase (Round \(reviewRound))\n\n"))

                            let modifiedFiles = WorkspaceScanner.listUncommittedSourceFiles(
                                workspacePath: workspacePath,
                                excludedPaths: context.excludedPaths
                            )

                            if modifiedFiles.isEmpty {
                                continuation.yield(.textDelta("No modified files remain. Review complete.\n"))
                                break
                            }

                            let (reReviewText, hasNewIssues) = await Self.runReReviewPhase(
                                modifiedFiles: modifiedFiles,
                                round: reviewRound,
                                context: context,
                                analysisProvider: analysisProvider,
                                maxWorkers: config.maxWorkers,
                                continuation: continuation,
                                isCancelled: isCancelled,
                                waitWhilePaused: waitWhilePaused
                            )

                            if !hasNewIssues || (testPassed && !hasNewIssues) {
                                continuation.yield(.textDelta("\n**All clear.** No new issues found.\n"))
                                break
                            }

                            // Parse new dynamic tasks for next round
                            currentTasks = Self.parseReviewTasks(
                                from: reReviewText,
                                filesToReview: modifiedFiles,
                                maxWorkers: config.maxWorkers
                            )

                            // Emit updated worker plan
                            for task in currentTasks {
                                continuation.yield(.raw(type: "review-worker-plan", payload: [
                                    "worker_id": task.id,
                                    "description": task.description,
                                    "severity": task.severity,
                                    "fileCount": "\(task.files.count)",
                                    "files": task.files.prefix(5).joined(separator: ", ")
                                        + (task.files.count > 5 ? " (+\(task.files.count - 5) more)" : "")
                                ]))
                            }

                            continuation.yield(.textDelta("\n**New issues found.** Proceeding to fix round \(reviewRound + 1) with \(currentTasks.count) worker(s)...\n"))
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
        filesToReview: [String],
        maxWorkers: Int,
        context: WorkspaceContext,
        analysisProvider: any LLMProvider,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        isCancelled: @Sendable @escaping () -> Bool,
        waitWhilePaused: @Sendable @escaping () async -> Void
    ) async -> String {
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
        }

        return fullText
    }

    // MARK: - Phase 2: Parse Review Tasks

    /// Extracts structured tasks from analysis output. Falls back to balanced split.
    static func parseReviewTasks(
        from analysisText: String,
        filesToReview: [String],
        maxWorkers: Int
    ) -> [ReviewTask] {
        // Try to extract JSON tasks from the analysis
        if let jsonTasks = extractReviewTasksJSON(from: analysisText) {
            if jsonTasks.isEmpty {
                return [] // LLM explicitly said no fixes needed
            }
            // Cap at maxWorkers
            return Array(jsonTasks.prefix(maxWorkers))
        }

        // Fallback: balanced split if JSON parsing failed
        return fallbackTasks(filesToReview: filesToReview, maxWorkers: maxWorkers)
    }

    /// Try to extract JSON review tasks from analysis text
    private static func extractReviewTasksJSON(from text: String) -> [ReviewTask]? {
        // Try markdown code block first: ```json ... ```
        let codeBlockPattern = #"```json\s*\n(\[[\s\S]*?\])\s*\n```"#
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let jsonRange = Range(match.range(at: 1), in: text) {
            let jsonStr = String(text[jsonRange])
            if let tasks = parseTasksJSON(jsonStr) {
                return tasks
            }
        }

        // Try bare JSON array near the end of text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lastBracket = trimmed.lastIndex(of: "]"),
           let firstBracket = trimmed[...lastBracket].lastIndex(of: "[") {
            let distanceToEnd = trimmed.distance(from: lastBracket, to: trimmed.endIndex)
            if distanceToEnd < 10 {
                let jsonStr = String(trimmed[firstBracket...lastBracket])
                if let tasks = parseTasksJSON(jsonStr) {
                    return tasks
                }
            }
        }

        return nil
    }

    /// Parse JSON string into ReviewTask array
    private static func parseTasksJSON(_ jsonStr: String) -> [ReviewTask]? {
        guard let data = jsonStr.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }

        var tasks: [ReviewTask] = []
        for (index, dict) in arr.enumerated() {
            let id = (dict["id"] as? String) ?? "review-\(index)"
            let description = (dict["description"] as? String) ?? "Fix issues in assigned files"
            let files = (dict["files"] as? [String]) ?? []
            let severity = (dict["severity"] as? String) ?? "warning"
            guard !files.isEmpty else { continue }
            tasks.append(ReviewTask(id: id, description: description, files: files, severity: severity))
        }
        // Return nil only if we had entries but all were empty-file tasks
        return tasks.isEmpty && !arr.isEmpty ? nil : tasks
    }

    /// Fallback: create tasks from balanced file splitting
    private static func fallbackTasks(filesToReview: [String], maxWorkers: Int) -> [ReviewTask] {
        guard !filesToReview.isEmpty else { return [] }
        let count = min(maxWorkers, filesToReview.count)
        let chunkSize = (filesToReview.count + count - 1) / count
        var tasks: [ReviewTask] = []
        for i in 0..<count {
            let start = i * chunkSize
            let end = min(start + chunkSize, filesToReview.count)
            guard start < end else { continue }
            let files = Array(filesToReview[start..<end])
            tasks.append(ReviewTask(
                id: "review-\(i)",
                description: "Fix issues in \(files.count) file(s)",
                files: files,
                severity: "warning"
            ))
        }
        return tasks
    }

    // MARK: - Phase 3: Parallel Fix

    /// Runs fix workers in parallel with file-lock coordination.
    /// Output is serialized: collected per-worker then emitted sequentially for linear chat.
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

        // Run workers in parallel, collect their events
        let workerResults: [(taskId: String, events: [StreamEvent])] = await withTaskGroup(
            of: (String, [StreamEvent]).self,
            returning: [(String, [StreamEvent])].self
        ) { group in
            for task in tasks {
                group.addTask {
                    if isCancelled() { return (task.id, []) }

                    // Acquire file locks
                    await fileLockCoordinator.acquireLock(
                        files: Set(task.files), swarmId: task.id
                    )

                    var collected: [StreamEvent] = []

                    // Emit started event for SwarmLiveReducer
                    collected.append(.raw(type: "agent", payload: [
                        "title": "Review Worker \(task.id)",
                        "detail": "started",
                        "swarm_id": task.id,
                        "group_id": "swarm-\(task.id)"
                    ]))

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
                                collected.append(.raw(type: type, payload: payload))
                            default:
                                collected.append(event)
                            }
                        }
                    } catch {
                        collected.append(.textDelta("\n**Worker \(task.id) error:** \(error.localizedDescription)\n"))
                    }

                    // Emit completed event for SwarmLiveReducer
                    collected.append(.raw(type: "agent", payload: [
                        "title": "Review Worker \(task.id)",
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

        // Serialize output: emit collected events one worker at a time for linear chat
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

    /// Streams re-review analysis and returns (fullText, hasNewIssues)
    private static func runReReviewPhase(
        modifiedFiles: [String],
        round: Int,
        context: WorkspaceContext,
        analysisProvider: any LLMProvider,
        maxWorkers: Int,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        isCancelled: @Sendable @escaping () -> Bool,
        waitWhilePaused: @Sendable @escaping () async -> Void
    ) async -> (String, Bool) {
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
        }

        let hasNewIssues = findingsContainIssues(fullText)
        return (fullText, hasNewIssues)
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

    /// Check if findings text contains actionable issues
    static func findingsContainIssues(_ text: String) -> Bool {
        let lower = text.lowercased()
        let noIssuesIndicators = ["no issues found", "all clear", "looks good", "no problems"]
        if noIssuesIndicators.contains(where: { lower.contains($0) }) && text.count < 200 {
            return false
        }
        let issueIndicators = ["critical", "warning", "bug", "fix", "issue", "error", "vulnerability", "severity"]
        return issueIndicators.contains(where: { lower.contains($0) })
    }

    /// Run test suite and optionally retry with debugger
    private static func runTests(
        context: WorkspaceContext,
        executionProvider: any LLMProvider,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        execController: ExecutionController?,
        isCancelled: @Sendable @escaping () -> Bool,
        waitWhilePaused: @Sendable @escaping () async -> Void
    ) async -> Bool {
        guard let cmd = TestProjectDetector.testCommand(workspacePath: context.workspacePath) else {
            continuation.yield(.textDelta("Project type not recognized for automatic test execution.\n"))
            return true // assume ok if we can't test
        }

        let maxAttempts = 2
        for attempt in 0..<maxAttempts {
            if isCancelled() { return false }
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
                let hasWarnings = lower.contains("warning:")
                let passed = (status == 0) && !hasWarnings

                if passed {
                    continuation.yield(.textDelta("**Tests passed successfully.**\n"))
                    return true
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
                return false
            }
        }
        return false
    }
}
