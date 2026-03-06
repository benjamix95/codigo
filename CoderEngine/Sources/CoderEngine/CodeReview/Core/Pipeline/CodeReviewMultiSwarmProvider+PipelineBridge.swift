import Foundation

extension CodeReviewMultiSwarmProvider {

    /// Entry point alternativo che usa la pipeline DAG per la fase di fix.
    /// Mantiene il flusso di analisi e parsing esistente, ma delega
    /// l'esecuzione parallela dei fix al PipelineFacade/WorkerPool.
    static func runReviewPipelineOrchestrated(
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

        let (promptWithoutScope, explicitScope) = Self.parseReviewScope(from: prompt)
        let (cleanPrompt, againstRef) = Self.parseAgainstRef(from: promptWithoutScope)
        let workspacePath = context.workspacePath

        continuation.yield(.started)

        let filesToReview: [String]
        let resolvedScope = explicitScope
            ?? Self.inferReviewScope(from: cleanPrompt) ?? .uncommitted
        if let ref = againstRef {
            guard Self.isValidAgainstRefFormat(ref) else {
                continuation.yield(.textDelta(
                    "Invalid AGAINST ref `\(ref)`.\n"
                ))
                continuation.yield(.completed); continuation.finish()
                return
            }
            let (diffFiles, diffError) = Self.gitDiffFiles(
                ref: ref, workspacePath: workspacePath,
                excludedPaths: context.excludedPaths
            )
            filesToReview = diffFiles
            if filesToReview.isEmpty {
                continuation.yield(.textDelta(
                    "\(diffError ?? "No changed files") against `\(ref)`.\n"
                ))
                continuation.yield(.completed); continuation.finish()
                return
            }
        } else {
            filesToReview = Self.resolveFiles(context: context, scope: resolvedScope)
            if filesToReview.isEmpty {
                let msg = resolvedScope == .staged
                    ? "No staged source files found.\n"
                    : "No uncommitted source files found.\n"
                continuation.yield(.textDelta(msg))
                continuation.yield(.completed); continuation.finish()
                return
            }
        }

        let scopeType: ReviewSessionScope.ScopeType = {
            if againstRef != nil { return .againstRef }
            return resolvedScope == .staged ? .staged : .uncommitted
        }()
        await sessionState.start(scope: ReviewSessionScope(
            type: scopeType, files: filesToReview, ref: againstRef
        ))

        _ = try await Self.runAnalysisPhase(
            cleanPrompt: cleanPrompt,
            againstRef: againstRef,
            filesToReview, config.maxWorkers,
            context: context,
            analysisProvider: analysisProvider,
            continuation: continuation,
            isCancelled: isCancelled,
            waitWhilePaused: waitWhilePaused
        )

        if isCancelled() {
            continuation.yield(.textDelta("\n**Review cancelled.**\n"))
            continuation.yield(.completed); continuation.finish()
            return
        }

        let pipelineScope: ReviewScope = againstRef != nil
            ? .againstRef
            : (resolvedScope == .staged ? .staged : .uncommitted)

        let (job, tasks) = PipelineJobFactory.fromCodeReview(
            scope: pipelineScope,
            filesToReview: filesToReview,
            workspace: workspacePath.path,
            analysisProviderId: analysisProvider.id,
            executionProviderId: executionProvider.id,
            maxWorkers: config.maxWorkers,
            maxRounds: config.maxReviewRounds
        )

        let facade = PipelineFacade()
        let adapter = AgentWorkerAdapter(
            provider: executionProvider,
            context: context,
            jobId: job.jobId
        )

        continuation.yield(.textDelta(
            "\nStarting pipeline-orchestrated fix phase "
            + "(\(filesToReview.count) files, \(config.maxWorkers) workers)...\n"
        ))

        let stream = await facade.executeJob(job, tasks: tasks, workerAdapter: adapter)
        for await event in stream {
            if isCancelled() {
                await facade.cancel()
                break
            }
            await waitWhilePaused()
            bridgeEventToStreamContinuation(event, continuation: continuation)
        }

        await sessionState.complete()
    }

    /// Mappa PipelineUIEvent in StreamEvent per il continuation della review.
    private static func bridgeEventToStreamContinuation(
        _ event: PipelineUIEvent,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) {
        switch event {
        case .taskStarted(let p):
            continuation.yield(.raw(type: "agent", payload: [
                "title": p.title,
                "detail": "started",
                "swarm_id": p.taskId,
                "group_id": "pipeline-\(p.taskId)"
            ]))
        case .taskCompleted(let p):
            continuation.yield(.raw(type: "agent", payload: [
                "title": p.agentName,
                "detail": "completed",
                "swarm_id": p.taskId,
                "group_id": "pipeline-\(p.taskId)"
            ]))
        case .textDelta(let p):
            continuation.yield(.textDelta(p.delta))
        case .textReplace(let p):
            continuation.yield(.textReplace(p.replacement))
        case .taskFailed(let p):
            continuation.yield(.textDelta(
                "\n[Task \(p.taskId) failed: \(p.error)]\n"
            ))
        case .jobCompleted(let p):
            continuation.yield(.textDelta(
                "\nPipeline review completed: "
                + "\(p.completedTasks)/\(p.totalTasks) tasks.\n"
            ))
            continuation.yield(.completed)
            continuation.finish()
        case .jobFailed(let p):
            continuation.yield(.textDelta(
                "\n[Pipeline review failed: \(p.reason)]\n"
            ))
            continuation.yield(.completed)
            continuation.finish()
        default:
            break
        }
    }
}
