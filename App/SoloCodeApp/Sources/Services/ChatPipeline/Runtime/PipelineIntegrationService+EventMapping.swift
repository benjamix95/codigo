import CoderEngine
import Foundation

extension PipelineIntegrationService {

    private static let canonicalTodoCompletionRoles: Set<AgentRole> = [
        .coder,
        .docWriter,
        .reviewer,
        .testWriter,
    ]

    func handleEvent(_ event: PipelineUIEvent, for conversationId: UUID) {
        #if DEBUG
        print("[ChatDebug] handleEvent: \(String(describing: event).prefix(200))")
        #endif
        switch event {
        case .jobStarted(let p):
            handleJobStarted(p, for: conversationId)
        case .jobCompleted(let p):
            handleJobCompleted(p, for: conversationId)
        case .jobFailed(let p):
            handleJobFailed(p, for: conversationId)
        case .taskStarted(let p):
            handleTaskStarted(p, for: conversationId)
        case .taskCompleted(let p):
            handleTaskCompleted(p, for: conversationId)
        case .taskFailed(let p):
            handleTaskFailed(p, for: conversationId)
        case .textDelta(let p):
            handleTextDelta(p, for: conversationId)
        case .textReplace(let p):
            handleTextReplace(p, for: conversationId)
        case .rawEvent(let p):
            handleRawEvent(p, for: conversationId)
        case .patchApplied(let p):
            handlePatchApplied(p, for: conversationId)
        case .rollbackTriggered(let p):
            handleRollback(p, for: conversationId)
        case .reviewFinding(let p):
            handleReviewFinding(p, for: conversationId)
        case .progressUpdate(let p):
            handleProgress(p, for: conversationId)
        case .circuitBreakerTriggered(let p):
            handleCircuitBreaker(p, for: conversationId)
        case .backpressureChanged(let p):
            handleBackpressure(p, for: conversationId)
        case .providerHealthChanged(let p):
            handleProviderHealth(p, for: conversationId)
        case .errorBudgetLow(let p):
            handleErrorBudget(p, for: conversationId)
        }
    }

    // MARK: - Job Handlers

    private func handleJobStarted(_ p: JobStartedPayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        runtime.cachedTaskRuntimeState = nil
        runtime.jobState = .intake
        runtime.totalTasks = p.taskCount
        runtime.completedTasks = 0
        persistSnapshot(for: conversationId)
        chatStore?.setLastAssistantStreaming(true, in: conversationId)
        chatStore?.setTaskStatus(
            "Pipeline started (\(p.taskCount) tasks, mode: \(p.mode.rawValue))",
            for: conversationId
        )
        consumePipelineUIEvent(.jobStarted(p), for: conversationId)
    }

    private func handleJobCompleted(_ p: JobCompletedPayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        runtime.jobState = .finalized
        runtime.completedTasks = p.completedTasks
        persistSnapshot(for: conversationId)
        consumePipelineUIEvent(.jobCompleted(p), for: conversationId)

        if let planId = runtime.planConversationId {
            finalizePlanBuild(
                agentConversationId: conversationId,
                planConversationId: planId,
                durationMs: p.durationMs,
                completedTasks: p.completedTasks,
                totalTasks: p.totalTasks
            )
        }

        swarmProgressStore?.clear(conversationId: conversationId)
    }

    private func handleJobFailed(_ p: JobFailedPayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        runtime.jobState = .failed
        runtime.lastError = p.reason
        persistSnapshot(for: conversationId)
        consumePipelineUIEvent(.jobFailed(p), for: conversationId)
    }

    // MARK: - Task Handlers

    private func handleTaskStarted(_ p: TaskStartedPayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        runtime.cachedTaskRuntimeState = nil
        runtime.jobState = .executing
        persistSnapshot(for: conversationId)
        consumePipelineUIEvent(.taskStarted(p), for: conversationId)
        recordStructuredPipelineTaskActivity(
            type: "pipeline_task_started",
            title: p.title,
            detail: "\(p.role.displayName): \(p.title)",
            conversationId: conversationId,
            isRunning: true,
            taskId: p.taskId
        )
        recordPipelineSwarmLifecycleActivity(
            agentName: p.agentName,
            title: p.title,
            detail: "\(p.role.displayName): \(p.title)",
            conversationId: conversationId,
            isRunning: true,
            taskId: p.taskId,
            status: "started"
        )
        swarmProgressStore?.markStarted(
            name: p.title,
            conversationId: conversationId
        )
        chatStore?.setTaskStatus(
            "\(p.role.displayName): \(p.title)",
            for: conversationId
        )
    }

    private func handleTaskCompleted(_ p: TaskCompletedPayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        runtime.cachedTaskRuntimeState = nil
        runtime.completedTasks += 1
        persistSnapshot(for: conversationId)
        consumePipelineUIEvent(.taskCompleted(p), for: conversationId)
        recordStructuredPipelineTaskActivity(
            type: "pipeline_task_completed",
            title: p.title,
            detail: "\(p.role.displayName): \(p.title) completed in \(p.durationMs)ms",
            conversationId: conversationId,
            isRunning: false,
            taskId: p.taskId
        )
        recordPipelineSwarmLifecycleActivity(
            agentName: p.agentName,
            title: p.title,
            detail: "\(p.role.displayName): \(p.title) completed in \(p.durationMs)ms",
            conversationId: conversationId,
            isRunning: false,
            taskId: p.taskId,
            status: "completed"
        )

        swarmProgressStore?.markCompleted(
            name: p.title,
            conversationId: conversationId
        )

        guard let todoStore else { return }

        if let planId = runtime.planConversationId {
            if Self.canonicalTodoCompletionRoles.contains(p.role) {
                var updated = todoStore.upsertCanonicalOnlyFromAgent(
                    id: nil,
                    title: p.title,
                    status: .done,
                    priority: nil,
                    notes: nil,
                    activeForm: nil,
                    linkedFiles: [],
                    conversationId: planId
                )
                if !updated {
                    updated = todoStore.upsertCanonicalFromExecutionFallback(
                        status: .done,
                        priority: nil,
                        notes: nil,
                        activeForm: nil,
                        linkedFiles: [],
                        conversationId: planId
                    )
                }
                if updated {
                    _ = todoStore.advanceNextCanonicalTodoIfNeeded(
                        conversationId: planId
                    )
                    let canonicalTodos = todoStore.canonicalTodos(for: planId)
                    chatStore?.syncPlanStepsFromCanonicalTodos(
                        canonicalTodos, in: planId
                    )
                }
            }
        } else if shouldPersistRuntimeTaskAsTodo(
            title: p.title.isEmpty ? p.agentName : p.title,
            runtime: runtime
        ) {
            todoStore.upsertFromAgent(
                id: nil,
                title: p.title.isEmpty ? p.agentName : p.title,
                status: .done,
                priority: nil,
                notes: nil,
                linkedFiles: [],
                conversationId: conversationId
            )
        }
    }

    private func handleTaskFailed(_ p: TaskFailedPayload, for conversationId: UUID) {
        if let runtime = runtime(for: conversationId) {
            runtime.cachedTaskRuntimeState = nil
            if let existing = runtime.lastError, !existing.isEmpty {
                if !existing.contains(p.error) {
                    runtime.lastError = "\(existing); \(p.error)"
                }
            } else {
                runtime.lastError = p.error
            }
            persistSnapshot(for: conversationId)
        }
        consumePipelineUIEvent(.taskFailed(p), for: conversationId)
        let failureTitle = p.title.trimmingCharacters(in: .whitespacesAndNewlines)
        recordStructuredPipelineTaskActivity(
            type: "pipeline_task_failed",
            title: failureTitle.isEmpty ? "Task failed" : failureTitle,
            detail: p.error,
            conversationId: conversationId,
            isRunning: false,
            taskId: p.taskId
        )
        recordPipelineSwarmLifecycleActivity(
            agentName: nil,
            title: failureTitle.isEmpty ? "Task failed" : failureTitle,
            detail: p.error,
            conversationId: conversationId,
            isRunning: false,
            taskId: p.taskId,
            status: "failed"
        )
        swarmProgressStore?.markFailed(name: failureTitle, conversationId: conversationId)
        chatStore?.setTaskStatus(
            failureTitle.isEmpty ? "Task failed: \(p.error)" : "\(failureTitle): \(p.error)",
            for: conversationId
        )
    }

    // MARK: - Text Handlers

    private func handleTextDelta(_ p: TextDeltaPayload, for conversationId: UUID) {
        let existingContent = runtime(for: conversationId)?
            .chatTurnState
            .textByStreamId[p.taskId]
        processInlinePolicyAckMarkersFromPipelineText(
            existingContent: existingContent,
            incomingContent: p.delta,
            isReplacement: false,
            conversationId: conversationId
        )
        processInlineTodoWriteMarkersFromPipelineText(
            existingContent: existingContent,
            incomingContent: p.delta,
            isReplacement: false,
            conversationId: conversationId
        )
        recordPipelineSubagentTextActivity(
            taskId: p.taskId,
            text: p.delta,
            conversationId: conversationId
        )
        consumePipelineUIEvent(.textDelta(p), for: conversationId)
    }

    private func handleTextReplace(_ p: TextReplacePayload, for conversationId: UUID) {
        processInlinePolicyAckMarkersFromPipelineText(
            existingContent: nil,
            incomingContent: p.replacement,
            isReplacement: true,
            conversationId: conversationId
        )
        processInlineTodoWriteMarkersFromPipelineText(
            existingContent: nil,
            incomingContent: p.replacement,
            isReplacement: true,
            conversationId: conversationId
        )
        recordPipelineSubagentTextActivity(
            taskId: p.taskId,
            text: p.replacement,
            conversationId: conversationId
        )
        consumePipelineUIEvent(.textReplace(p), for: conversationId)
    }
}
