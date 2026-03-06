import CoderEngine
import Foundation

extension PipelineIntegrationService {

    // MARK: - Raw Events

    func handleRawEvent(_ p: RawEventPayload, for conversationId: UUID) {
        let rawType = p.rawType

        let providerId = runtime(for: conversationId)?.currentJobId ?? "pipeline"
        if let callback = onRawStreamEvent {
            callback(rawType, p.payload, providerId, conversationId)
        }
        consumeRawPipelineArtifacts(rawType: rawType, payload: p.payload, for: conversationId)

        if rawType == "todo_write" || p.payload.keys.contains(where: {
            $0.hasPrefix("todo_")
        }) {
            handleRawTodoWrite(p, for: conversationId)
        } else if isDebugRawEvent(p) {
            handleRawDebugEvent(p, for: conversationId)
        } else if rawType == "plan_step" {
            handleRawPlanStep(p, for: conversationId)
        } else if rawType == "show_task_panel" {
            chatStore?.setTaskStatus(
                p.payload["status"] ?? "Working...",
                for: conversationId
            )
        } else {
            forwardRawEventToTaskActivity(p, for: conversationId)
        }
    }

    private func forwardRawEventToTaskActivity(
        _ p: RawEventPayload,
        for conversationId: UUID
    ) {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "pipeline",
            type: p.rawType,
            payload: p.payload
        )
        taskActivityStore?.addEnvelope(envelope)
        for event in envelope.events {
            if case .taskActivity(let activity) = event {
                taskActivityStore?.addActivity(
                    scopedTaskActivity(activity, conversationId: conversationId)
                )
            }
        }
    }

    private func handleRawTodoWrite(_ p: RawEventPayload, for conversationId: UUID) {
        guard let todoStore, let runtime = runtime(for: conversationId) else { return }

        let parsedTodo = EventNormalizer.parseTodoWrite(payload: p.payload)
        let title = parsedTodo?.title ?? p.payload["title"] ?? p.taskId
        let status = parsedTodo?.status ?? .inProgress
        let todoId = resolvedRawTodoID(from: p, parsedTodo: parsedTodo)
        let priority = parsedTodo?.priority
        let activeForm = parsedTodo?.activeForm
        let linkedFiles = parsedTodo?.files ?? []

        if let planId = runtime.planConversationId {
            var updated = todoStore.upsertCanonicalOnlyFromAgent(
                id: todoId,
                title: title,
                status: status,
                priority: priority,
                notes: p.payload["notes"],
                activeForm: activeForm,
                linkedFiles: linkedFiles,
                conversationId: planId
            )
            if !updated {
                updated = todoStore.upsertCanonicalFromExecutionFallback(
                    status: status,
                    priority: priority,
                    notes: p.payload["notes"],
                    activeForm: activeForm,
                    linkedFiles: linkedFiles,
                    conversationId: planId
                )
            }
            if updated, status == .done {
                _ = todoStore.advanceNextCanonicalTodoIfNeeded(
                    conversationId: planId
                )
                let canonicalTodos = todoStore.canonicalTodos(for: planId)
                chatStore?.syncPlanStepsFromCanonicalTodos(
                    canonicalTodos,
                    in: planId
                )
            }
        } else {
            todoStore.upsertFromAgent(
                id: todoId,
                title: title,
                status: status,
                priority: priority,
                notes: p.payload["notes"],
                activeForm: activeForm,
                linkedFiles: linkedFiles,
                conversationId: conversationId
            )
        }
    }

    private func resolvedRawTodoID(
        from payload: RawEventPayload,
        parsedTodo: TodoWritePayload?
    ) -> UUID? {
        if let direct = parsedTodo?.id {
            return direct
        }
        return UUID(uuidString: payload.taskId)
    }

    private func handleRawPlanStep(_ p: RawEventPayload, for conversationId: UUID) {
        guard let planId = runtime(for: conversationId)?.planConversationId else { return }
        guard let todoStore else { return }

        let canonicalTodos = todoStore.canonicalTodos(for: planId)
        chatStore?.syncPlanStepsFromCanonicalTodos(canonicalTodos, in: planId)
    }

    private func isDebugRawEvent(_ p: RawEventPayload) -> Bool {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "pipeline",
            type: p.rawType,
            payload: p.payload
        )
        return envelope.events.contains(where: { DebugProjectionEventConsumer.handles($0) })
    }

    private func handleRawDebugEvent(_ p: RawEventPayload, for conversationId: UUID) {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "pipeline",
            type: p.rawType,
            payload: p.payload
        )
        taskActivityStore?.addEnvelope(envelope)

        for event in envelope.events {
            switch event {
            case .taskActivity(let activity):
                taskActivityStore?.addActivity(
                    scopedTaskActivity(activity, conversationId: conversationId)
                )
            default:
                guard DebugProjectionEventConsumer.handles(event) else { continue }
                applyOrBufferDebugEvent(event, for: conversationId)
            }
        }
    }

    private func scopedTaskActivity(
        _ activity: TaskActivity,
        conversationId: UUID
    ) -> TaskActivity {
        var payload = activity.payload
        payload["conversation_id"] = conversationId.uuidString
        return TaskActivity(
            id: activity.id,
            type: activity.type,
            title: activity.title,
            detail: activity.detail,
            payload: payload,
            timestamp: activity.timestamp,
            phase: activity.phase,
            isRunning: activity.isRunning,
            groupId: activity.groupId
        )
    }

    // MARK: - Plan Build Finalization

    func finalizePlanBuild(
        agentConversationId: UUID,
        planConversationId planId: UUID,
        durationMs: Int,
        completedTasks: Int,
        totalTasks: Int
    ) {
        guard let todoStore else { return }

        consumePipelineEvents(
            [
                ChatPipelineEvent(
                    conversationId: agentConversationId,
                    assistantMessageId: runtime(for: agentConversationId)?.assistantMessageId ?? UUID(),
                    turnId: runtime(for: agentConversationId)?.chatTurnState.turnId ?? UUID().uuidString,
                    sequence: 0,
                    source: "pipeline",
                    kind: .statusBadge,
                    payload: [
                        "artifact_id": "plan-build-summary",
                        "title": "Plan build complete",
                        "detail": buildPlanRecap(
                            durationMs: durationMs,
                            completedTasks: completedTasks,
                            totalTasks: totalTasks
                        ),
                    ]
                ),
            ],
            for: agentConversationId
        )

        todoStore.upsertFromAgent(
            id: nil,
            title: "Code Review & Test",
            status: .pending,
            priority: .high,
            notes: "Review all pipeline changes and run tests",
            linkedFiles: [],
            conversationId: planId
        )

        let canonicalTodos = todoStore.canonicalTodos(for: planId)
        chatStore?.syncPlanStepsFromCanonicalTodos(canonicalTodos, in: planId)
    }

    private func buildPlanRecap(
        durationMs: Int,
        completedTasks: Int,
        totalTasks: Int
    ) -> String {
        let duration = formatDuration(durationMs)
        return "\n\n---\n**Plan Build Complete** (\(duration))"
            + "\n\(completedTasks)/\(totalTasks) tasks completed."
            + "\nPlease review the changes and run tests."
    }

    // MARK: - Patch & Rollback

    func handlePatchApplied(_ p: PatchAppliedPayload, for conversationId: UUID) {
        for file in p.touchedFiles {
            consumePipelineEvents(
                [
                    ChatPipelineEvent(
                        conversationId: conversationId,
                        assistantMessageId: runtime(for: conversationId)?.assistantMessageId ?? UUID(),
                        turnId: runtime(for: conversationId)?.chatTurnState.turnId ?? UUID().uuidString,
                        sequence: 0,
                        source: "pipeline",
                        kind: .filesArtifact,
                        payload: ["path": file]
                    ),
                ],
                for: conversationId
            )
        }
    }

    func handleRollback(_ p: RollbackPayload, for conversationId: UUID) {
        consumePipelineEvents(
            [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: runtime(for: conversationId)?.assistantMessageId ?? UUID(),
                    turnId: runtime(for: conversationId)?.chatTurnState.turnId ?? UUID().uuidString,
                    sequence: 0,
                    source: "pipeline",
                    kind: .statusBadge,
                    payload: [
                        "artifact_id": "rollback-\(p.taskId)",
                        "title": "Rollback triggered",
                        "detail": p.reason,
                    ]
                ),
            ],
            for: conversationId
        )
    }

    // MARK: - Review & Progress

    func handleReviewFinding(_ p: ReviewFindingPayload, for conversationId: UUID) {
        consumePipelineEvents(
            [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: runtime(for: conversationId)?.assistantMessageId ?? UUID(),
                    turnId: runtime(for: conversationId)?.chatTurnState.turnId ?? UUID().uuidString,
                    sequence: 0,
                    source: "pipeline",
                    kind: .toolTraceArtifact,
                    payload: [
                        "artifact_id": "review-finding-\(p.jobId)-\(p.taskId)-\(p.finding.findingId)",
                        "title": "Review finding",
                        "detail": "[\(p.finding.severity.rawValue.uppercased())] \(p.finding.file): \(p.finding.message)",
                    ]
                ),
            ],
            for: conversationId
        )
    }

    func handleProgress(_ p: ProgressPayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        runtime.completedTasks = p.completedTasks
        runtime.totalTasks = p.totalTasks
        runtime.jobState = p.currentState
        persistSnapshot(for: conversationId)
    }

    // MARK: - Diagnostics

    func handleCircuitBreaker(_ p: CircuitBreakerPayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        runtime.circuitBreakerActive = (p.phase == .open)
        persistSnapshot(for: conversationId)
        consumePipelineEvents(
            [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: runtime.assistantMessageId,
                    turnId: runtime.chatTurnState.turnId,
                    sequence: 0,
                    source: "pipeline",
                    kind: .statusBadge,
                    payload: [
                        "artifact_id": "circuit-breaker",
                        "title": "Circuit breaker",
                        "detail": "\(p.phase.rawValue) - \(p.reason)",
                    ]
                ),
            ],
            for: conversationId
        )
    }

    func handleBackpressure(_ p: BackpressurePayload, for conversationId: UUID) {
        let status = p.active ? "active" : "cleared"
        chatStore?.setTaskStatus(
            "Backpressure \(status) (\(p.activeWorkers)/\(p.maxWorkers) workers)",
            for: conversationId
        )
    }

    func handleProviderHealth(_ p: ProviderHealthPayload, for conversationId: UUID) {
        if p.status == .unhealthy {
            consumePipelineEvents(
                [
                    ChatPipelineEvent(
                        conversationId: conversationId,
                        assistantMessageId: runtime(for: conversationId)?.assistantMessageId ?? UUID(),
                        turnId: runtime(for: conversationId)?.chatTurnState.turnId ?? UUID().uuidString,
                        sequence: 0,
                        source: "pipeline",
                        kind: .statusBadge,
                        payload: [
                            "artifact_id": "provider-health-\(p.providerId)",
                            "title": "Provider unhealthy",
                            "detail": p.providerId,
                        ]
                    ),
                ],
                for: conversationId
            )
        }
    }

    func handleErrorBudget(_ p: ErrorBudgetPayload, for conversationId: UUID) {
        consumePipelineEvents(
            [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: runtime(for: conversationId)?.assistantMessageId ?? UUID(),
                    turnId: runtime(for: conversationId)?.chatTurnState.turnId ?? UUID().uuidString,
                    sequence: 0,
                    source: "pipeline",
                    kind: .statusBadge,
                    payload: [
                        "artifact_id": "error-budget",
                        "title": "Error budget low",
                        "detail": "\(p.failedPercent)%/\(p.maxPercent)%, \(p.consecutiveFailures) consecutive failures",
                    ]
                ),
            ],
            for: conversationId
        )
    }

    func formatDuration(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        let seconds = Double(ms) / 1000.0
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let minutes = Int(seconds) / 60
        let remaining = Int(seconds) % 60
        return "\(minutes)m \(remaining)s"
    }
}
