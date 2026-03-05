import Foundation

extension CodeReviewMultiSwarmProvider {
    static func runReviewPipeline(
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

        let (promptWithoutScopeMarker, explicitScope) = Self.parseReviewScope(from: prompt)
        let (cleanPrompt, againstRef) = Self.parseAgainstRef(from: promptWithoutScopeMarker)
        let workspacePath = context.workspacePath

        continuation.yield(.started)

        // Wire session state: mark as analyzing
        let resolvedScopeType: ReviewSessionScope.ScopeType = {
            if againstRef != nil { return .againstRef }
            let scope = explicitScope ?? Self.inferReviewScope(from: cleanPrompt) ?? .uncommitted
            return scope == .staged ? .staged : .uncommitted
        }()

        let filesToReview: [String]
        let resolvedScope = explicitScope ?? Self.inferReviewScope(from: cleanPrompt) ?? .uncommitted
        if let ref = againstRef {
            guard Self.isValidAgainstRefFormat(ref) else {
                continuation.yield(.textDelta("Invalid AGAINST ref `\(ref)`. Use values like `HEAD~1`, `abc123`, or `main..feature`.\n"))
                continuation.yield(.completed)
                continuation.finish()
                return
            }
            let (diffFiles, diffError) = Self.gitDiffFiles(ref: ref, workspacePath: workspacePath, excludedPaths: context.excludedPaths)
            filesToReview = diffFiles
            if filesToReview.isEmpty {
                let reason = diffError ?? "No changed files found"
                continuation.yield(.textDelta("\(reason) against `\(ref)`.\n"))
                continuation.yield(.completed)
                continuation.finish()
                return
            }
        } else {
            filesToReview = Self.resolveFiles(context: context, scope: resolvedScope)
            if filesToReview.isEmpty {
                let message: String = switch resolvedScope {
                case .staged:
                    "No staged source files found. Nothing to review.\n"
                case .uncommitted:
                    "No uncommitted source files found. Nothing to review.\n"
                }
                continuation.yield(.textDelta(message))
                continuation.yield(.completed)
                continuation.finish()
                return
            }
        }

        // Wire session state: start session with resolved scope
        await sessionState.start(scope: ReviewSessionScope(
            type: resolvedScopeType,
            files: filesToReview,
            ref: againstRef
        ))

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

        let taskExtraction = Self.parseReviewTasks(
            from: analysisText,
            filesToReview: filesToReview,
            maxWorkers: config.maxWorkers
        )

        let tasks: [ReviewTask]
        var extractionInconclusiveReason: String?
        switch taskExtraction {
        case .noFixes:
            tasks = []
        case .noPayload(let reason):
            continuation.yield(.textDelta("\n**Review task extraction inconclusive:** \(reason)\n"))
            extractionInconclusiveReason = reason
            tasks = []
        case .tasks(let parsedTasks):
            tasks = parsedTasks
        case .invalidJSON(let reason):
            continuation.yield(.textDelta("\n**Review task extraction inconclusive:** Could not parse task JSON: \(reason)\n"))
            extractionInconclusiveReason = reason
            tasks = []
        }

        // Feed parsed tasks into session state as findings
        let parsedFindings = tasks.map { task in
            CodeReviewFinding.fromRawTask(
                id: task.id,
                description: task.description,
                files: task.files,
                severity: task.severity,
                filePath: task.files.first,
                lineNumber: nil
            )
        }
        if !parsedFindings.isEmpty {
            await sessionState.addFindings(parsedFindings)
        }

        await Self.executeReviewLoop(
            tasks: tasks,
            extractionInconclusiveReason: extractionInconclusiveReason,
            config: config,
            context: context,
            executionProvider: executionProvider,
            analysisProvider: analysisProvider,
            fileLockCoordinator: fileLockCoordinator,
            continuation: continuation,
            execController: execController,
            isCancelled: isCancelled,
            waitWhilePaused: waitWhilePaused
        )

        // Wire session state: mark completion
        await sessionState.complete()
    }
}
