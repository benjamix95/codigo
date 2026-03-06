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

        continuation.yield(.started)

        let filesToReview = resolveFiles(
            context: context,
            resolvedScope: resolvedScope,
            againstRef: againstRef,
            workspacePath: workspacePath,
            continuation: continuation
        )
        guard !filesToReview.isEmpty else {
            continuation.yield(.completed)
            continuation.finish()
            return
        }

        let scopeType: ReviewSessionScope.ScopeType = {
            if againstRef != nil { return .againstRef }
            return resolvedScope == .staged ? .staged : .uncommitted
        }()
        await sessionState.start(scope: ReviewSessionScope(
            type: scopeType,
            files: filesToReview,
            ref: againstRef
        ))
        await sessionState.markAnalysisStarted()

        let analysisText = try await CodeReviewMultiSwarmProvider.runAnalysisPhase(
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

        if isCancelled() {
            continuation.yield(.textDelta("\n**Review cancelled.**\n"))
            continuation.yield(.completed)
            continuation.finish()
            return
        }

        await sessionState.markAnalysisCompleted()
        let taskExtraction = CodeReviewMultiSwarmProvider.parseReviewTasks(
            from: analysisText,
            filesToReview: filesToReview,
            maxWorkers: config.maxWorkers
        )

        let initialTasks: [CodeReviewMultiSwarmProvider.ReviewTask]
        let extractionInconclusiveReason: String?
        switch taskExtraction {
        case .noFixes:
            initialTasks = []
            extractionInconclusiveReason = nil
        case .noPayload(let reason):
            continuation.yield(.textDelta("\n**Review task extraction inconclusive:** \(reason)\n"))
            initialTasks = []
            extractionInconclusiveReason = reason
        case .invalidJSON(let reason):
            continuation.yield(.textDelta("\n**Review task extraction inconclusive:** Could not parse task JSON: \(reason)\n"))
            initialTasks = []
            extractionInconclusiveReason = reason
        case .tasks(let tasks):
            initialTasks = tasks
            extractionInconclusiveReason = nil
        }

        if !initialTasks.isEmpty {
            let findings = initialTasks.map { task in
                CodeReviewFinding.fromRawTask(
                    id: task.id,
                    description: task.description,
                    files: task.files,
                    severity: task.severity,
                    filePath: task.files.first
                )
            }
            await sessionState.addFindings(findings)
        }

        if config.enabledPhases == .analysisOnly {
            continuation.yield(.textDelta("\n---\n**Analysis complete.** (Analysis-only mode)\n"))
            await sessionState.complete()
            continuation.yield(.completed)
            continuation.finish()
            return
        }

        let completed = await runRounds(
            initialTasks: initialTasks,
            extractionInconclusiveReason: extractionInconclusiveReason,
            context: context,
            config: config,
            againstRef: againstRef,
            resolvedScope: resolvedScope,
            executionProvider: executionProvider,
            analysisProvider: analysisProvider,
            execController: execController,
            fileLockCoordinator: fileLockCoordinator,
            sessionState: sessionState,
            continuation: continuation,
            isCancelled: isCancelled,
            waitWhilePaused: waitWhilePaused
        )

        if completed {
            await sessionState.complete()
        } else if (await sessionState.snapshot()).phase != .failed {
            await sessionState.fail(error: "Review pipeline did not complete successfully.")
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
                continuation.yield(.textDelta("\(error ?? "No changed files") against `\(againstRef)`.\n"))
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

}
