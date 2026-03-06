import Foundation

extension ReviewPipelineCoordinator {
    func runPipelineFixStage(
        tasks: [CodeReviewMultiSwarmProvider.ReviewTask],
        context: WorkspaceContext,
        executionProvider: any LLMProvider,
        config: MultiSwarmReviewConfig,
        againstRef: String?,
        resolvedScope: CodeReviewMultiSwarmProvider.ReviewFileScope,
        round: Int,
        sessionState: CodeReviewSessionState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        isCancelled: @escaping @Sendable () -> Bool,
        waitWhilePaused: @escaping @Sendable () async -> Void
    ) async -> Bool {
        let pipelineScope: ReviewScope = againstRef != nil
            ? .againstRef
            : (resolvedScope == .staged ? .staged : .uncommitted)
        let sessionId = await sessionState.snapshot().sessionId
        let (job, pipelineTasks) = PipelineJobFactory.fromCodeReviewTasks(
            scope: pipelineScope,
            reviewTasks: tasks,
            workspace: context.workspacePath.path,
            providerId: executionProvider.id,
            sessionId: sessionId,
            round: round,
            maxWorkers: config.maxWorkers
        )

        await sessionState.setCurrentJobId(job.jobId)
        let facade = PipelineFacade()
        let adapter = AgentWorkerAdapter(
            provider: executionProvider,
            context: context,
            jobId: job.jobId
        )

        var activeWorkers = 0
        var failureReason: String?
        let stream = await facade.executeJob(job, tasks: pipelineTasks, workerAdapter: adapter)
        for await event in stream {
            if isCancelled() {
                await facade.cancel()
                break
            }
            await waitWhilePaused()
            switch event {
            case .taskStarted(let payload):
                activeWorkers += 1
                await sessionState.setActiveWorkerCount(activeWorkers)
                await sessionState.markWorkerSpawned(workerId: payload.taskId, title: payload.title)
            case .taskCompleted(let payload):
                activeWorkers = max(0, activeWorkers - 1)
                await sessionState.setActiveWorkerCount(activeWorkers)
                await sessionState.markWorkerCompleted(workerId: payload.taskId, title: payload.title)
            case .taskFailed(let payload):
                activeWorkers = max(0, activeWorkers - 1)
                await sessionState.setActiveWorkerCount(activeWorkers)
                await sessionState.markWorkerCompleted(workerId: payload.taskId, title: payload.error)
            case .jobFailed(let payload):
                failureReason = payload.reason
            default:
                break
            }
            bridgePipelineEvent(
                event,
                sessionId: sessionId,
                continuation: continuation
            )
        }

        await sessionState.setActiveWorkerCount(0)
        if let failureReason {
            await sessionState.fail(error: failureReason)
            return false
        }
        return true
    }

    func bridgePipelineEvent(
        _ event: PipelineUIEvent,
        sessionId: String,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) {
        switch event {
        case .taskStarted(let payload):
            continuation.yield(.raw(type: "agent", payload: [
                "title": payload.title,
                "detail": "started",
                "swarm_id": payload.taskId,
                "group_id": "review-\(sessionId)-\(payload.taskId)",
                "session_id": sessionId,
            ]))
        case .taskCompleted(let payload):
            continuation.yield(.raw(type: "agent", payload: [
                "title": payload.agentName,
                "detail": "completed",
                "swarm_id": payload.taskId,
                "group_id": "review-\(sessionId)-\(payload.taskId)",
                "session_id": sessionId,
            ]))
        case .taskFailed(let payload):
            continuation.yield(.raw(type: "agent", payload: [
                "title": payload.taskId,
                "detail": "failed",
                "status": "failed",
                "swarm_id": payload.taskId,
                "group_id": "review-\(sessionId)-\(payload.taskId)",
                "session_id": sessionId,
            ]))
            continuation.yield(.textDelta("\n[Task \(payload.taskId) failed: \(payload.error)]\n"))
        case .textDelta(let payload):
            continuation.yield(.textDelta(payload.delta))
        case .textReplace(let payload):
            continuation.yield(.textReplace(payload.replacement))
        default:
            break
        }
    }
}
