import CoderEngine
import Foundation

private enum InlineTodoWriteMatcher {
    static let regex = try? NSRegularExpression(
        pattern: #"\[CODERIDE:todo_write\|([^\]]+)\]"#,
        options: [.caseInsensitive]
    )
}

func inlinePolicyAckHashesForStreamingUpdate(
    existingContent: String?,
    incomingContent: String,
    isReplacement: Bool
) -> [String] {
    guard !incomingContent.isEmpty else { return [] }
    let combinedContent = isReplacement
        ? incomingContent
        : (existingContent ?? "") + incomingContent
    return inlinePolicyAckHashes(in: combinedContent)
}

func inlineTodoWritePayloadsForStreamingUpdate(
    existingContent: String?,
    incomingContent: String,
    isReplacement: Bool
) -> [[String: String]] {
    guard !incomingContent.isEmpty,
          let regex = InlineTodoWriteMatcher.regex else {
        return []
    }

    let prefix = isReplacement ? "" : (existingContent ?? "")
    let combinedContent = prefix + incomingContent
    let nsContent = combinedContent as NSString
    let prefixLength = (prefix as NSString).length

    var payloads: [[String: String]] = []
    let matches = regex.matches(
        in: combinedContent,
        range: NSRange(location: 0, length: nsContent.length)
    )

    for match in matches where match.numberOfRanges >= 2 {
        if !isReplacement, match.range.location + match.range.length <= prefixLength {
            continue
        }
        let rawArgs = nsContent.substring(with: match.range(at: 1))
        let payload = parseInlineCoderideKeyValueArgs(rawArgs)
        guard EventNormalizer.parseTodoWrite(payload: payload) != nil else { continue }
        payloads.append(payload)
    }
    return payloads
}

func pipelineSwarmPayload(
    taskId: String,
    agentName: String?,
    status: String
) -> [String: String] {
    var payload: [String: String] = [
        "task_id": taskId,
        "swarm_id": taskId,
        "group_id": "swarm-\(taskId)",
        "status": status,
        "owner_kind": "worker",
        "presentation_role": "subagent",
    ]
    let normalizedAgentName = (agentName ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if !normalizedAgentName.isEmpty {
        payload["agent_name"] = normalizedAgentName
    }
    return payload
}

private func parseInlineCoderideKeyValueArgs(_ rawArgs: String) -> [String: String] {
    var payload: [String: String] = [:]
    for segment in rawArgs.split(separator: "|", omittingEmptySubsequences: false) {
        let parts = segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { continue }
        let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !value.isEmpty else { continue }
        payload[key] = value
    }
    return payload
}

extension PipelineIntegrationService {
    private func processInlinePolicyAckMarkersFromPipelineText(
        existingContent: String?,
        incomingContent: String,
        isReplacement: Bool,
        conversationId: UUID
    ) {
        guard let runtime = runtime(for: conversationId),
              let callback = runtime.rawEventHandler else {
            return
        }

        let hashes = inlinePolicyAckHashesForStreamingUpdate(
            existingContent: existingContent,
            incomingContent: incomingContent,
            isReplacement: isReplacement
        )
        guard !hashes.isEmpty else { return }

        let providerId = runtime.chatTurnState.providerId ?? runtime.providerId
        for hash in hashes {
            callback("policy_ack", ["hash": hash], providerId, conversationId)
        }
    }

    private func processInlineTodoWriteMarkersFromPipelineText(
        existingContent: String?,
        incomingContent: String,
        isReplacement: Bool,
        conversationId: UUID
    ) {
        guard let runtime = runtime(for: conversationId),
              let callback = runtime.rawEventHandler else {
            return
        }

        let payloads = inlineTodoWritePayloadsForStreamingUpdate(
            existingContent: existingContent,
            incomingContent: incomingContent,
            isReplacement: isReplacement
        )
        guard !payloads.isEmpty else { return }

        let providerId = runtime.chatTurnState.providerId ?? runtime.providerId
        for payload in payloads {
            callback("todo_write", payload, providerId, conversationId)
        }
    }

    private func recordPipelineSwarmLifecycleActivity(
        agentName: String?,
        title: String,
        detail: String,
        conversationId: UUID,
        isRunning: Bool,
        taskId: String,
        status: String
    ) {
        let resolvedName = (agentName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = resolvedName.isEmpty
            ? title.trimmingCharacters(in: .whitespacesAndNewlines)
            : resolvedName
        var payload = pipelineSwarmPayload(
            taskId: taskId,
            agentName: agentName,
            status: status
        )
        payload["conversation_id"] = conversationId.uuidString.lowercased()
        if !detail.isEmpty {
            payload["detail"] = detail
        }
        taskActivityStore?.addActivity(
            TaskActivity(
                type: "agent",
                title: resolvedTitle.isEmpty ? "Subagent" : resolvedTitle,
                detail: detail,
                payload: payload,
                phase: .executing,
                isRunning: isRunning,
                groupId: payload["group_id"]
            )
        )
    }

    private func recordPipelineSubagentTextActivity(
        taskId: String,
        text: String,
        conversationId: UUID
    ) {
        let cleaned = ChatStore.stripCoderideMarkers(text, aggressive: true)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        var payload = pipelineSwarmPayload(
            taskId: taskId,
            agentName: nil,
            status: "running"
        )
        payload["conversation_id"] = conversationId.uuidString.lowercased()
        payload["text"] = cleaned

        taskActivityStore?.addActivity(
            TaskActivity(
                type: "subagent_text",
                title: "Subagent update",
                detail: String(cleaned.prefix(140)),
                payload: payload,
                phase: .executing,
                isRunning: true,
                groupId: payload["group_id"]
            )
        )
    }

    private func recordStructuredPipelineTaskActivity(
        type: String,
        title: String,
        detail: String,
        conversationId: UUID,
        isRunning: Bool,
        taskId: String
    ) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: [String: String] = [
            "conversation_id": conversationId.uuidString.lowercased(),
            "task_id": taskId,
            "group_id": taskId,
            "status": isRunning ? "running" : "completed",
            "owner_kind": "supervisor",
            "supervisor_kind": "orchestrator",
        ]
        taskActivityStore?.addActivity(
            TaskActivity(
                type: type,
                title: normalizedTitle.isEmpty ? "Pipeline task" : normalizedTitle,
                detail: detail,
                payload: payload,
                phase: .executing,
                isRunning: isRunning,
                groupId: taskId
            )
        )
    }

    private static let canonicalTodoCompletionRoles: Set<AgentRole> = [
        .coder,
        .docWriter,
        .reviewer,
        .testWriter,
    ]

    func handleEvent(_ event: PipelineUIEvent, for conversationId: UUID) {
        print("[ChatDebug] handleEvent: \(String(describing: event).prefix(200))")
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

    private func handleJobStarted(_ p: JobStartedPayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
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

    private func handleTaskStarted(_ p: TaskStartedPayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
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

    private func shouldPersistRuntimeTaskAsTodo(
        title: String,
        runtime: PipelineConversationRuntime
    ) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return false }
        if runtime.planConversationId == nil && max(runtime.totalTasks, 1) <= 1 {
            return false
        }
        return true
    }

    private func handleTaskFailed(_ p: TaskFailedPayload, for conversationId: UUID) {
        consumePipelineUIEvent(.taskFailed(p), for: conversationId)
        recordStructuredPipelineTaskActivity(
            type: "pipeline_task_failed",
            title: "Task failed",
            detail: p.error,
            conversationId: conversationId,
            isRunning: false,
            taskId: p.taskId
        )
        recordPipelineSwarmLifecycleActivity(
            agentName: nil,
            title: "Task failed",
            detail: p.error,
            conversationId: conversationId,
            isRunning: false,
            taskId: p.taskId,
            status: "failed"
        )
    }

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
