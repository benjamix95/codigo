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
        if ReviewCoreBridge.isEnabled {
            try await ReviewPipelineRustDriver(
                prompt: prompt,
                context: context,
                config: config,
                analysisProvider: analysisProvider,
                executionProvider: executionProvider,
                runtimeResolver: runtimeResolver,
                execController: execController,
                fileLockCoordinator: fileLockCoordinator,
                sessionState: sessionState,
                continuation: continuation
            ).run()
            return
        }

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
            switch resolvedScope {
            case .staged:
                return .staged
            case .workspace:
                return .workspace
            case .uncommitted:
                return .uncommitted
            }
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

}
