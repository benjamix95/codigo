import Foundation

extension ReviewPipelineCoordinator {
    func runPipelineFixStage(
        tasks: [CodeReviewMultiSwarmProvider.ReviewTask],
        context: WorkspaceContext,
        executionProvider: any LLMProvider,
        config: MultiSwarmReviewConfig,
        againstRef: String?,
        resolvedScope: CodeReviewMultiSwarmProvider.ReviewFileScope,
        fileLockCoordinator: FileLockCoordinator,
        round: Int,
        sessionState: CodeReviewSessionState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        isCancelled: @escaping @Sendable () -> Bool,
        waitWhilePaused: @escaping @Sendable () async -> Void
    ) async -> Bool {
        let pipelineScope: ReviewScope = againstRef != nil
            ? .againstRef
            : {
                switch resolvedScope {
                case .staged:
                    return .staged
                case .workspace:
                    return .workspace
                case .uncommitted:
                    return .uncommitted
                }
            }()
        let sessionId = await sessionState.snapshot().sessionId
        let taskBatches = nonOverlappingReviewTaskBatches(tasks)
        var activeWorkers = 0

        for batch in taskBatches {
            if isCancelled() {
                await sessionState.setActiveWorkerCount(0)
                return false
            }
            let reservedLocks = await reserveReviewTaskLocks(
                batch,
                coordinator: fileLockCoordinator,
                isCancelled: isCancelled
            )
            guard reservedLocks else {
                await sessionState.fail(error: "Unable to acquire review file locks for fix stage.")
                await sessionState.setActiveWorkerCount(0)
                return false
            }

            let (job, pipelineTasks) = PipelineJobFactory.fromCodeReviewTasks(
                scope: pipelineScope,
                reviewTasks: batch,
                workspace: context.workspacePath.path,
                providerId: executionProvider.id,
                sessionId: sessionId,
                round: round,
                maxWorkers: min(config.maxWorkers, max(batch.count, 1))
            )
            await sessionState.setCurrentJobId(job.jobId)
            let facade = PipelineFacade()
            let adapter = AgentWorkerAdapter(
                provider: executionProvider,
                context: context,
                jobId: job.jobId
            )

            var failureReason: String?
            let stream = await facade.executeJob(job, tasks: pipelineTasks, workerAdapter: adapter)
            for await event in stream {
                if isCancelled() {
                    await facade.cancel()
                    failureReason = "Review cancelled."
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

            if let failureReason {
                await releaseReviewTaskLocks(batch, coordinator: fileLockCoordinator)
                await sessionState.setActiveWorkerCount(0)
                await sessionState.fail(error: failureReason)
                return false
            }
            await releaseReviewTaskLocks(batch, coordinator: fileLockCoordinator)
        }
        await sessionState.setActiveWorkerCount(0)
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

    private func nonOverlappingReviewTaskBatches(
        _ tasks: [CodeReviewMultiSwarmProvider.ReviewTask]
    ) -> [[CodeReviewMultiSwarmProvider.ReviewTask]] {
        var batches: [[CodeReviewMultiSwarmProvider.ReviewTask]] = []

        for task in tasks {
            let fileSet = Set(task.files)
            if let batchIndex = batches.firstIndex(where: { batch in
                batch.allSatisfy { Set($0.files).isDisjoint(with: fileSet) }
            }) {
                batches[batchIndex].append(task)
            } else {
                batches.append([task])
            }
        }

        return batches
    }

    private func reserveReviewTaskLocks(
        _ tasks: [CodeReviewMultiSwarmProvider.ReviewTask],
        coordinator: FileLockCoordinator,
        isCancelled: @escaping @Sendable () -> Bool
    ) async -> Bool {
        for task in tasks {
            let acquired = await coordinator.acquireLock(
                files: Set(task.files),
                swarmId: task.id,
                isCancelled: isCancelled
            )
            guard acquired else {
                await releaseReviewTaskLocks(tasks, coordinator: coordinator)
                return false
            }
        }
        return true
    }

    private func releaseReviewTaskLocks(
        _ tasks: [CodeReviewMultiSwarmProvider.ReviewTask],
        coordinator: FileLockCoordinator
    ) async {
        for task in tasks {
            await coordinator.releaseLock(files: Set(task.files), swarmId: task.id)
        }
    }
}
