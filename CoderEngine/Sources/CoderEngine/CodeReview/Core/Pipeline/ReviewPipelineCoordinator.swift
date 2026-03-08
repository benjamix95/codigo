import Foundation

public actor ReviewPipelineCoordinator {
    public static let shared = ReviewPipelineCoordinator()

    public init() {}

    public func run(
        prompt: String,
        context: WorkspaceContext,
        config: MultiSwarmReviewConfig,
        analysisProvider: any LLMProvider,
        executionProvider: any LLMProvider,
        runtimeResolver: CodeReviewRuntimeResolver?,
        execController: ExecutionController?,
        fileLockCoordinator: FileLockCoordinator,
        sessionState: CodeReviewSessionState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
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

        let (promptWithoutScopeMarker, explicitScope) =
            CodeReviewMultiSwarmProvider.parseReviewScope(from: prompt)
        let (cleanPrompt, againstRef) =
            CodeReviewMultiSwarmProvider.parseAgainstRef(from: promptWithoutScopeMarker)
        let resolvedScope = explicitScope
            ?? CodeReviewMultiSwarmProvider.inferReviewScope(from: cleanPrompt)
            ?? .uncommitted
        let workspacePath = context.workspacePath
        let initialRuntimeResources = await currentRuntimeResources(
            staticConfig: config,
            staticAnalysisProvider: analysisProvider,
            staticExecutionProvider: executionProvider,
            runtimeResolver: runtimeResolver,
            sessionState: sessionState
        )
        let initialConfig = initialRuntimeResources.config

        continuation.yield(.started)

        let filesToReview = resolveFiles(
            context: context,
            resolvedScope: resolvedScope,
            againstRef: againstRef,
            workspacePath: workspacePath,
            continuation: continuation
        )
        let scopeType: ReviewSessionScope.ScopeType = {
            if againstRef != nil { return .againstRef }
            return resolvedScope == .staged ? .staged : .uncommitted
        }()
        await sessionState.start(scope: ReviewSessionScope(
            type: scopeType,
            files: filesToReview,
            ref: againstRef
        ), workspacePath: workspacePath.path)
        guard !filesToReview.isEmpty else {
            await sessionState.complete()
            continuation.yield(.completed)
            continuation.finish()
            return
        }

        let auditFindings = await self.runAuditStage(
            filesToReview: filesToReview,
            workspacePath: workspacePath,
            sessionState: sessionState,
            continuation: continuation
        )
        let auditCandidates = auditFindings.map {
            ReviewCandidateVerificationService.candidate(from: $0, signalType: .pattern)
        }
        if !auditCandidates.isEmpty {
            await sessionState.addCandidates(auditCandidates)
            await verifyCandidates(
                auditCandidates,
                workspacePath: workspacePath,
                filesToReview: filesToReview,
                sessionState: sessionState
            )
        }
        await sessionState.markAnalysisStarted()

        let analysisText = try await CodeReviewMultiSwarmProvider.runAnalysisPhase(
            cleanPrompt: cleanPrompt,
            scopeDescription: reviewScopeDescription(
                scope: resolvedScope,
                againstRef: againstRef
            ),
            filesToReview,
            initialConfig.maxWorkers,
            context: context,
            analysisProvider: initialRuntimeResources.analysisProvider,
            continuation: continuation,
            isCancelled: isCancelled,
            waitWhilePaused: waitWhilePaused
        )

        if isCancelled() {
            await sessionState.fail(error: "Review cancelled.")
            continuation.yield(.textDelta("\n**Review cancelled.**\n"))
            continuation.yield(.completed)
            continuation.finish()
            return
        }

        await sessionState.markAnalysisCompleted()
        let taskExtraction = CodeReviewMultiSwarmProvider.parseReviewTasks(
            from: analysisText,
            filesToReview: filesToReview,
            maxWorkers: initialConfig.maxWorkers
        )

        let initialTasks: [CodeReviewMultiSwarmProvider.ReviewTask]
        let extractionFailureReason: String?
        switch taskExtraction {
        case .noFixes:
            initialTasks = []
            extractionFailureReason = nil
        case .noPayload(let reason):
            continuation.yield(.textDelta("\n**Review task extraction failed:** \(reason)\n"))
            initialTasks = []
            extractionFailureReason = reason
        case .invalidJSON(let reason):
            continuation.yield(.textDelta("\n**Review task extraction failed:** Could not parse task JSON: \(reason)\n"))
            initialTasks = []
            extractionFailureReason = "Could not parse task JSON: \(reason)"
        case .tasks(let tasks):
            initialTasks = tasks
            extractionFailureReason = nil
        }

        if !initialTasks.isEmpty {
            let candidates = initialTasks.map { reviewCandidate(from: $0, prefix: "r0-") }
            await sessionState.addCandidates(candidates)
            await verifyCandidates(
                candidates,
                workspacePath: workspacePath,
                filesToReview: filesToReview,
                sessionState: sessionState
            )
        }
        if let extractionFailureReason {
            let fallbackFile = filesToReview.first ?? "review-scope"
            await sessionState.addFinding(CodeReviewFinding(
                severity: .warning,
                category: .other,
                origin: .reviewer,
                filePath: fallbackFile,
                message: "Structured review task extraction failed: \(extractionFailureReason)",
                blocking: false
            ))
            await sessionState.fail(error: "Review task extraction failed: \(extractionFailureReason)")
            continuation.yield(.completed)
            continuation.finish()
            return
        }

        if config.enabledPhases == .analysisOnly {
            continuation.yield(.textDelta("\n---\n**Analysis complete.** (Analysis-only mode)\n"))
            await sessionState.complete()
            continuation.yield(.completed)
            continuation.finish()
            return
        }

        let outcome = await runRounds(
            initialTasks: initialTasks,
            context: context,
            config: config,
            againstRef: againstRef,
            resolvedScope: resolvedScope,
            staticAnalysisProvider: analysisProvider,
            staticExecutionProvider: executionProvider,
            runtimeResolver: runtimeResolver,
            execController: execController,
            fileLockCoordinator: fileLockCoordinator,
            sessionState: sessionState,
            continuation: continuation,
            isCancelled: isCancelled,
            waitWhilePaused: waitWhilePaused
        )

        switch outcome {
        case .completed:
            await sessionState.complete()
        case .cancelled:
            await sessionState.fail(error: "Review cancelled.")
        case .failed(let reason):
            if (await sessionState.snapshot()).phase != .failed {
                await sessionState.fail(error: reason)
            }
        }
    }

    func currentRuntimeResources(
        staticConfig: MultiSwarmReviewConfig,
        staticAnalysisProvider: any LLMProvider,
        staticExecutionProvider: any LLMProvider,
        runtimeResolver: CodeReviewRuntimeResolver?,
        sessionState: CodeReviewSessionState
    ) async -> CodeReviewRuntimeResources {
        let sessionConfig = await sessionState.snapshot().config
        if let runtimeResolver,
           let resolved = runtimeResolver(sessionConfig) {
            return resolved
        }
        return CodeReviewRuntimeResources(
            config: staticConfig,
            analysisProvider: staticAnalysisProvider,
            executionProvider: staticExecutionProvider
        )
    }

    func runAuditStage(
        filesToReview: [String],
        workspacePath: URL,
        sessionState: CodeReviewSessionState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async -> [CodeReviewFinding] {
        guard !filesToReview.isEmpty else { return [] }

        let toolNames = ReviewAuditToolName.all
        for toolName in toolNames {
            await sessionState.markAuditStarted(toolName: toolName)
        }

        let results = await withTaskGroup(
            of: ReviewAuditToolResult.self,
            returning: [ReviewAuditToolResult].self
        ) { group in
            for toolName in toolNames {
                group.addTask {
                    CodeReviewAuditService.runTool(
                        named: toolName,
                        scopeFiles: filesToReview,
                        workspacePath: workspacePath
                    )
                }
            }

            var aggregated: [ReviewAuditToolResult] = []
            for await result in group {
                aggregated.append(result)
            }
            return aggregated
        }

        var findings: [CodeReviewFinding] = []
        for result in results.sorted(by: { $0.toolName < $1.toolName }) {
            let sessionId = await sessionState.snapshot().sessionId
            await sessionState.recordAuditResult(result)
            findings.append(contentsOf: result.findings)
            continuation.yield(.raw(type: "review-audit-tool", payload: [
                "tool": result.toolName,
                "session_id": sessionId,
                "findings_count": String(result.findings.count),
                "blocking_findings": String(result.blockingFindingsCount),
                "coverage": result.coverageAvailable ? "true" : "false",
                "duration_ms": String(result.durationMs),
                "detail": result.summary,
            ]))
        }

        return CodeReviewAuditService.deduplicate(findings)
    }

    private func reviewScopeDescription(
        scope: CodeReviewMultiSwarmProvider.ReviewFileScope,
        againstRef: String?
    ) -> String {
        if let againstRef {
            return "Changes against `\(againstRef)`"
        }
        switch scope {
        case .staged:
            return "Staged changes"
        case .uncommitted:
            return "Uncommitted changes"
        }
    }

    private func resolveFiles(
        context: WorkspaceContext,
        resolvedScope: CodeReviewMultiSwarmProvider.ReviewFileScope,
        againstRef: String?,
        workspacePath: URL,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) -> [String] {
        if let againstRef {
            guard CodeReviewMultiSwarmProvider.isValidAgainstRefFormat(againstRef) else {
                continuation.yield(.textDelta("Invalid AGAINST ref `\(againstRef)`.\n"))
                return []
            }
            let (files, error) = CodeReviewMultiSwarmProvider.gitDiffFiles(
                ref: againstRef,
                workspacePath: workspacePath,
                excludedPaths: context.excludedPaths
            )
            if files.isEmpty {
                let currentHead = currentHEADRevision(workspacePath: workspacePath)
                let message = Self.noFilesAgainstRefMessage(
                    againstRef: againstRef,
                    normalizedInput: CodeReviewMultiSwarmProvider.normalizedAgainstRefInput(againstRef),
                    currentHeadRevision: currentHead,
                    error: error
                )
                continuation.yield(.textDelta(message + "\n"))
            }
            return files
        }

        let files = CodeReviewMultiSwarmProvider.resolveFiles(
            context: context,
            scope: resolvedScope
        )
        if files.isEmpty {
            let message = resolvedScope == .staged
                ? "No staged source files found.\n"
                : "No uncommitted source files found.\n"
            continuation.yield(.textDelta(message))
        }
        return files
    }

    static func noFilesAgainstRefMessage(
        againstRef: String,
        normalizedInput: String,
        currentHeadRevision: String?,
        error: String?
    ) -> String {
        if let error, !error.isEmpty {
            return "\(error) against `\(againstRef)`."
        }

        let trimmedRef = againstRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSingleCommitRange = normalizedInput != trimmedRef
        let matchesHeadCommit = currentHeadRevision.map {
            $0 == trimmedRef || $0.hasPrefix(trimmedRef) || trimmedRef.hasPrefix($0)
        } ?? false

        if isSingleCommitRange && matchesHeadCommit {
            return "No changed source files for `\(againstRef)`. The ref resolves to the current `HEAD` commit, so the review was reinterpreted as the single-commit range `\(normalizedInput)`."
        }
        if isSingleCommitRange {
            return "No changed source files for `\(againstRef)`. The review was reinterpreted as the single-commit range `\(normalizedInput)`."
        }
        return "No changed source files against `\(againstRef)`."
    }

    private func currentHEADRevision(workspacePath: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "HEAD"]
        process.currentDirectoryURL = workspacePath

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }

}
