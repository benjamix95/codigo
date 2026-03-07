import Foundation

// MARK: - Task Scheduling

extension OrchestratorMainLoop {

    func scheduleReadyTasks(job: PipelineJob) async {
        let readyTasks = await scheduler.getReadyTasks()

        for task in readyTasks {
            let atCapacity = await workerPool.isAtCapacity
            if atCapacity {
                await backpressure.activate(.workerQueueFull)
                await emitEvent(
                    type: .schedulerBackpressure,
                    jobId: job.jobId,
                    taskId: task.taskId
                )
                break
            }

            let role = nextAgentRole(for: task, job: job)

            let hasCapacity = await swarmBudget.hasCapacity(
                task: task,
                role: role
            )
            guard hasCapacity else { continue }

            let scope = LockScope(from: task)
            let lockAcquired = await lockManager.acquire(
                scope: scope,
                taskId: task.taskId
            )
            guard lockAcquired else {
                await scheduler.markWaiting(task.taskId)
                continue
            }

            await emitEvent(
                type: .lockAcquired,
                jobId: job.jobId,
                taskId: task.taskId
            )

            let agentName = await nameAssigner.assign(task: task, role: role)

            await scheduler.updateTaskStatus(task.taskId, status: .running)
            _ = await swarmBudget.reserve(task: task, role: role)

            let taskId = task.taskId
            let jobId = job.jobId

            let work: @Sendable () async -> WorkerTaskResult
            if let adapter = workerAdapter {
                work = await adapter.makeWorkClosure(
                    task: task, agentName: agentName, role: role
                )
            } else {
                work = Self.stubClosure(
                    taskId: taskId, agentName: agentName, role: role
                )
            }

            do {
                try await workerPool.dispatch(
                    taskId: taskId,
                    agentName: agentName,
                    agentRole: role,
                    work: work
                )
            } catch {
                await scheduler.setPreferredAgentRole(taskId, role: role)
                await scheduler.updateTaskStatus(taskId, status: .pending)
                await swarmBudget.release(task: task, role: role)
                await lockManager.release(taskId: taskId)

                await emitEvent(
                    type: .lockReleased,
                    jobId: jobId,
                    taskId: taskId
                )
                continue
            }

            await emitEvent(
                type: .taskStarted,
                jobId: jobId,
                taskId: taskId,
                payload: ["agent_name": agentName, "role": role.rawValue]
            )
        }

        let isAtCap = await workerPool.isAtCapacity
        if !isAtCap {
            await backpressure.deactivate(.workerQueueFull)
        }
    }

    /// Determina il prossimo ruolo agente per un task (basato sul flusso §5.5).
    func nextAgentRole(
        for task: TaskNode,
        job: PipelineJob
    ) -> AgentRole {
        roleStrategy.nextRole(for: task, job: job)
    }

    /// Stub di fallback usato nei test quando nessun adapter e' iniettato.
    static func stubClosure(
        taskId: String,
        agentName: String,
        role: AgentRole
    ) -> @Sendable () async -> WorkerTaskResult {
        { WorkerTaskResult(
            taskId: taskId,
            agentName: agentName,
            agentRole: role,
            success: true,
            durationMs: 0
        ) }
    }
}
