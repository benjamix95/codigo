import Foundation

// MARK: - Result Handling

extension OrchestratorMainLoop {

    func handleResult(_ result: WorkerTaskResult, job: PipelineJob) async {
        await swarmBudget.release(
            task: TaskNode(taskId: result.taskId, title: ""),
            role: result.agentRole
        )
        await lockManager.release(taskId: result.taskId)

        await emitEvent(
            type: .lockReleased,
            jobId: job.jobId,
            taskId: result.taskId
        )

        if result.success {
            consecutiveFailures = 0
            await handleSuccessResult(result, job: job)
        } else {
            consecutiveFailures += 1
            await handleFailureResult(result, job: job)
        }
    }

    private func handleSuccessResult(
        _ result: WorkerTaskResult,
        job: PipelineJob
    ) async {
        await emitEvent(
            type: .taskCompleted,
            jobId: job.jobId,
            taskId: result.taskId,
            payload: [
                "agent_name": result.agentName,
                "duration_ms": "\(result.durationMs)",
                "role": result.agentRole.rawValue
            ]
        )

        if result.agentRole == .explorer {
            await scheduler.markContextEnriched(result.taskId)
        }

        let task = await scheduler.task(byId: result.taskId) ??
            TaskNode(taskId: result.taskId, title: "")

        let completionData = Self.extractCompletionData(from: result)

        let action = completionHandler.handleSuccess(
            result: result,
            task: task,
            hasCriticalFindings: completionData.hasCriticalFindings,
            testsPass: completionData.testsPass,
            shouldInvokeDocWriter: completionData.shouldInvokeDocWriter
        )

        await applyAction(action, job: job)
    }

    private func handleFailureResult(
        _ result: WorkerTaskResult,
        job: PipelineJob
    ) async {
        await emitEvent(
            type: .taskFailed,
            jobId: job.jobId,
            taskId: result.taskId,
            payload: ["error": result.error ?? "unknown"]
        )

        let task = await scheduler.task(byId: result.taskId) ??
            TaskNode(taskId: result.taskId, title: "")

        let totalTasks = await scheduler.taskCount
        let failedCount = await scheduler.countByStatus(.failed) + 1

        let action = completionHandler.handleFailure(
            result: result,
            task: task,
            consecutiveFailures: consecutiveFailures,
            errorBudget: job.errorBudget,
            totalTasks: totalTasks,
            failedTaskCount: failedCount
        )
        if case .retryTask(let taskId, _) = action {
            await scheduler.setPreferredAgentRole(taskId, role: result.agentRole)
        }

        await applyAction(action, job: job)
    }

    // MARK: - Apply Action

    func applyAction(_ action: CompletionAction, job: PipelineJob) async {
        switch action {
        case .scheduleNextAgent(let taskId, let role):
            await scheduler.setPreferredAgentRole(taskId, role: role)
            await scheduler.updateTaskStatus(taskId, status: .pending)

        case .scheduleFixRound(let taskId, _):
            await scheduler.setPreferredAgentRole(taskId, role: nil)
            await scheduler.scheduleRetry(taskId)

        case .transitionToValidation(let taskId):
            await scheduler.setPreferredAgentRole(taskId, role: nil)
            await scheduler.updateTaskStatus(taskId, status: .completed)

        case .blockTask(let taskId, _):
            await scheduler.setPreferredAgentRole(taskId, role: nil)
            await scheduler.updateTaskStatus(taskId, status: .blocked)

        case .retryTask(let taskId, let delayMs):
            await scheduler.scheduleRetry(taskId, delayMs: delayMs)

        case .failTask(let taskId, _):
            await scheduler.setPreferredAgentRole(taskId, role: nil)
            await scheduler.updateTaskStatus(taskId, status: .failed)

        case .abortJob(let reason):
            do {
                try await stateMachine.abort(reason: reason)
            } catch {
                NSLog("[OrchestratorMainLoop] applyAction abort failed: %@", "\(error)")
            }

        case .continueNormally:
            break
        }
    }

    // MARK: - Completion Data Extraction

    struct CompletionData {
        let hasCriticalFindings: Bool
        let testsPass: Bool
        let shouldInvokeDocWriter: Bool
    }

    static func extractCompletionData(
        from result: WorkerTaskResult
    ) -> CompletionData {
        guard let envelope = result.envelope else {
            return CompletionData(
                hasCriticalFindings: false,
                testsPass: true,
                shouldInvokeDocWriter: false
            )
        }

        let summaries = envelope.actions.compactMap(\.summary).joined(separator: " ").lowercased()

        let hasCritical = summaries.contains("critical")
            || summaries.contains("security vulnerability")
            || summaries.contains("blocking issue")

        let testsFail = summaries.contains("tests fail")
            || summaries.contains("test failure")
            || summaries.contains("build error")

        let needsDoc = envelope.actions.contains { $0.type == .docUpdate || $0.type == .docFlowUpdate }
            || summaries.contains("documentation needed")
            || summaries.contains("doc update")

        return CompletionData(
            hasCriticalFindings: hasCritical,
            testsPass: !testsFail,
            shouldInvokeDocWriter: needsDoc
        )
    }

    // MARK: - Events

    func emitEvent(
        type: PipelineEventType,
        jobId: String,
        taskId: String? = nil,
        payload: [String: String] = [:]
    ) async {
        let event = EventBusEvent(
            eventId: "evt_\(tickCount)_\(type.rawValue)",
            jobId: jobId,
            taskId: taskId,
            type: type,
            payload: payload,
            idempotencyKey: "\(jobId)_\(type.rawValue)_\(tickCount)_\(taskId ?? "none")"
        )
        try? await eventBus.publish(event)
    }
}
