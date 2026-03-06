import CoderEngine
import Foundation

// MARK: - Event Mapping

extension PipelineIntegrationService {
    private static let canonicalTodoCompletionRoles: Set<AgentRole> = [
        .coder,
        .docWriter,
        .reviewer,
        .testWriter,
    ]

    func handleEvent(_ event: PipelineUIEvent, for conversationId: UUID) {
        // #region agent log
        Self._eventCounter += 1
        let eventName: String
        switch event {
        case .textDelta: eventName = "textDelta"
        case .textReplace: eventName = "textReplace"
        case .rawEvent(let p): eventName = "rawEvent(\(p.rawType))"
        case .jobStarted: eventName = "jobStarted"
        case .jobCompleted: eventName = "jobCompleted"
        case .jobFailed: eventName = "jobFailed"
        case .taskStarted: eventName = "taskStarted"
        case .taskCompleted: eventName = "taskCompleted"
        case .taskFailed: eventName = "taskFailed"
        default: eventName = "other"
        }
        if Self._eventCounter <= 30 {
            PipelineIntegrationService.debugLog("H6H8", "handleEvent", ["event": eventName, "count": Self._eventCounter])
        }
        // #endregion

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

    // MARK: - Job Events

    private func handleJobStarted(_ p: JobStartedPayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        runtime.jobState = .intake
        runtime.totalTasks = p.taskCount
        runtime.completedTasks = 0
        persistSnapshot(for: conversationId)
        // #region agent log
        PipelineIntegrationService.debugLog("H7", "handleJobStarted — setting streaming=true", ["conversationId": conversationId.uuidString])
        // #endregion
        chatStore?.setLastAssistantStreaming(true, in: conversationId)
        chatStore?.setTaskStatus(
            "Pipeline started (\(p.taskCount) tasks, mode: \(p.mode.rawValue))",
            for: conversationId
        )
    }

    private func handleJobCompleted(_ p: JobCompletedPayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        runtime.jobState = .finalized
        runtime.completedTasks = p.completedTasks
        persistSnapshot(for: conversationId)

        let summary = "Pipeline completed: \(p.completedTasks)/\(p.totalTasks) tasks"
            + " in \(formatDuration(p.durationMs))"
        appendToAssistantMessage(summary, in: conversationId)

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

        let errorMsg = "\n\n[Pipeline Error: \(p.reason)]"
            + " (\(p.failedTasks) task(s) failed)"
        appendToAssistantMessage(errorMsg, in: conversationId)
    }

    // MARK: - Task Events

    private func handleTaskStarted(_ p: TaskStartedPayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        runtime.jobState = .executing
        persistSnapshot(for: conversationId)
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
        runtime.completedTasks += 1
        persistSnapshot(for: conversationId)

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

    private func shouldPersistRuntimeTaskAsTodo(
        title: String,
        runtime: PipelineConversationRuntime
    ) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return false }
        // Generic agent chat jobs always use a single implicit pipeline task.
        // Persisting that as a todo duplicates the task card and leaks it into chat.
        if runtime.planConversationId == nil && max(runtime.totalTasks, 1) <= 1 {
            return false
        }
        return true
    }

    private func handleTaskFailed(_ p: TaskFailedPayload, for conversationId: UUID) {
        let errorLine = "\n[Task \(p.taskId) failed: \(p.error)]"
        appendToAssistantMessage(errorLine, in: conversationId)
    }

    // MARK: - Streaming Events

    private func handleTextDelta(_ p: TextDeltaPayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        let current = runtime.accumulatedText[p.taskId, default: ""]
        runtime.accumulatedText[p.taskId] = current + p.delta

        let fullText = runtime.accumulatedText.values.joined()
        chatStore?.updateLastAssistantMessage(
            content: fullText,
            in: conversationId,
            persistImmediately: false
        )
    }

    private func handleTextReplace(_ p: TextReplacePayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        runtime.accumulatedText[p.taskId] = p.replacement

        let fullText = runtime.accumulatedText.values.joined()
        chatStore?.updateLastAssistantMessage(
            content: fullText,
            in: conversationId,
            persistImmediately: false
        )
    }
}
