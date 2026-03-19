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
        let sessionId = await sessionState.snapshot().sessionId
        guard let plan = planFixStage(
            tasks: tasks,
            againstRef: againstRef,
            resolvedScope: resolvedScope,
            sessionId: sessionId
        ) else {
            await sessionState.fail(error: "Rust fix-stage planner unavailable.")
            await sessionState.setActiveWorkerCount(0)
            return false
        }
        let pipelineScope = plan.pipelineScope
        let taskBatches = plan.taskBatches
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
                for bridgedEvent in bridgedPipelineEvents(event, sessionId: sessionId) {
                    continuation.yield(bridgedEvent)
                }
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

    func bridgedPipelineEvents(
        _ event: PipelineUIEvent,
        sessionId: String
    ) -> [StreamEvent] {
        guard let response = ReviewFixStageRustBridge.bridgeEvent(event, sessionId: sessionId) else {
            return []
        }
        var events: [StreamEvent] = []
        if let rawType = response.rawType,
           let rawPayload = response.rawPayload {
            events.append(.raw(type: rawType, payload: rawPayload))
        }
        if let textDelta = response.textDelta {
            events.append(.textDelta(textDelta))
        }
        if let textReplace = response.textReplace {
            events.append(.textReplace(textReplace))
        }
        return events
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

    func planFixStage(
        tasks: [CodeReviewMultiSwarmProvider.ReviewTask],
        againstRef: String?,
        resolvedScope: CodeReviewMultiSwarmProvider.ReviewFileScope,
        sessionId: String
    ) -> ReviewFixStageRustPlanResult? {
        guard let response = ReviewFixStageRustBridge.plan(
            tasks: tasks,
            againstRef: againstRef,
            resolvedScope: resolvedScope.rawValue,
            sessionId: sessionId
        ) else {
            return nil
        }
        guard let pipelineScope = ReviewScope(rawValue: response.pipelineScope ?? "uncommitted") else {
            return nil
        }
        return ReviewFixStageRustPlanResult(
            pipelineScope: pipelineScope,
            taskBatches: response.taskBatches
        )
    }
}

struct ReviewFixStageRustPlanResult {
    let pipelineScope: ReviewScope
    let taskBatches: [[CodeReviewMultiSwarmProvider.ReviewTask]]
}

private enum ReviewFixStageRustBridge {
    static func plan(
        tasks: [CodeReviewMultiSwarmProvider.ReviewTask],
        againstRef: String?,
        resolvedScope: String,
        sessionId: String
    ) -> ReviewFixStageRustPlanResponse? {
        let response: ReviewFixStageRustPlanResponse? = ReviewCoreBridge.call(
            functionName: "review_core_fix_stage_plan",
            request: ReviewFixStageRustPlanRequest(
                schemaVersion: 1,
                sessionId: sessionId,
                resolvedScope: resolvedScope,
                againstRef: againstRef,
                tasks: tasks
            )
        )
        guard response?.error == nil else { return nil }
        return response
    }

    static func bridgeEvent(
        _ event: PipelineUIEvent,
        sessionId: String
    ) -> ReviewFixStageRustEventResponse? {
        let request: ReviewFixStageRustEventRequest
        switch event {
        case .taskStarted(let payload):
            request = ReviewFixStageRustEventRequest(
                schemaVersion: 1,
                sessionId: sessionId,
                eventKind: "task_started",
                taskId: payload.taskId,
                title: payload.title
            )
        case .taskCompleted(let payload):
            request = ReviewFixStageRustEventRequest(
                schemaVersion: 1,
                sessionId: sessionId,
                eventKind: "task_completed",
                taskId: payload.taskId,
                agentName: payload.agentName
            )
        case .taskFailed(let payload):
            request = ReviewFixStageRustEventRequest(
                schemaVersion: 1,
                sessionId: sessionId,
                eventKind: "task_failed",
                taskId: payload.taskId,
                error: payload.error
            )
        case .textDelta(let payload):
            request = ReviewFixStageRustEventRequest(
                schemaVersion: 1,
                sessionId: sessionId,
                eventKind: "text_delta",
                delta: payload.delta
            )
        case .textReplace(let payload):
            request = ReviewFixStageRustEventRequest(
                schemaVersion: 1,
                sessionId: sessionId,
                eventKind: "text_replace",
                replacement: payload.replacement
            )
        default:
            return nil
        }
        let response: ReviewFixStageRustEventResponse? = ReviewCoreBridge.call(
            functionName: "review_core_fix_stage_bridge_event",
            request: request
        )
        guard response?.error == nil else { return nil }
        return response
    }
}

private struct ReviewFixStageRustPlanRequest: Encodable {
    let schemaVersion: Int
    let sessionId: String
    let resolvedScope: String
    let againstRef: String?
    let tasks: [CodeReviewMultiSwarmProvider.ReviewTask]
}

private struct ReviewFixStageRustPlanResponse: Decodable {
    let error: ReviewFixStageRustError?
    let pipelineScope: String?
    let taskBatches: [[CodeReviewMultiSwarmProvider.ReviewTask]]
}

private struct ReviewFixStageRustEventRequest: Encodable {
    let schemaVersion: Int
    let sessionId: String
    let eventKind: String
    var taskId: String?
    var title: String?
    var agentName: String?
    var error: String?
    var delta: String?
    var replacement: String?
}

private struct ReviewFixStageRustEventResponse: Decodable {
    let error: ReviewFixStageRustError?
    let rawType: String?
    let rawPayload: [String: String]?
    let textDelta: String?
    let textReplace: String?
}

private struct ReviewFixStageRustError: Decodable {
    let code: String
    let message: String
}
