import CoderEngine
import Foundation

// MARK: - Event Mapping

extension PipelineIntegrationService {

    func handleEvent(_ event: PipelineUIEvent) async {
        switch event {
        case .jobStarted(let p):
            handleJobStarted(p)
        case .jobCompleted(let p):
            handleJobCompleted(p)
        case .jobFailed(let p):
            handleJobFailed(p)
        case .taskStarted(let p):
            handleTaskStarted(p)
        case .taskCompleted(let p):
            handleTaskCompleted(p)
        case .taskFailed(let p):
            handleTaskFailed(p)
        case .textDelta(let p):
            handleTextDelta(p)
        case .textReplace(let p):
            handleTextReplace(p)
        case .patchApplied(let p):
            handlePatchApplied(p)
        case .rollbackTriggered(let p):
            handleRollback(p)
        case .reviewFinding(let p):
            handleReviewFinding(p)
        case .progressUpdate(let p):
            handleProgress(p)
        case .circuitBreakerTriggered(let p):
            handleCircuitBreaker(p)
        case .backpressureChanged(let p):
            handleBackpressure(p)
        case .providerHealthChanged(let p):
            handleProviderHealth(p)
        case .errorBudgetLow(let p):
            handleErrorBudget(p)
        }
    }

    // MARK: - Job Events

    private func handleJobStarted(_ p: JobStartedPayload) {
        jobState = .intake
        totalTasks = p.taskCount
        completedTasks = 0
        chatStore?.setTaskStatus(
            "Pipeline started (\(p.taskCount) tasks, mode: \(p.mode.rawValue))",
            for: conversationId
        )
    }

    private func handleJobCompleted(_ p: JobCompletedPayload) {
        jobState = .finalized
        completedTasks = p.completedTasks

        let summary = "Pipeline completed: \(p.completedTasks)/\(p.totalTasks) tasks"
            + " in \(formatDuration(p.durationMs))"
        appendToAssistantMessage(summary)

        swarmProgressStore?.clear(conversationId: conversationId)
    }

    private func handleJobFailed(_ p: JobFailedPayload) {
        jobState = .failed
        lastError = p.reason

        let errorMsg = "\n\n[Pipeline Error: \(p.reason)]"
            + " (\(p.failedTasks) task(s) failed)"
        appendToAssistantMessage(errorMsg)
    }

    // MARK: - Task Events

    private func handleTaskStarted(_ p: TaskStartedPayload) {
        jobState = .executing
        swarmProgressStore?.markStarted(
            name: p.title,
            conversationId: conversationId
        )
        chatStore?.setTaskStatus(
            "\(p.role.displayName): \(p.title)",
            for: conversationId
        )
    }

    private func handleTaskCompleted(_ p: TaskCompletedPayload) {
        completedTasks += 1
        let taskTitle = accumulatedText[p.taskId] != nil
            ? p.taskId : p.agentName
        swarmProgressStore?.markCompleted(
            name: taskTitle,
            conversationId: conversationId
        )

        if let todoStore, let convId = conversationId {
            todoStore.upsertFromAgent(
                id: nil,
                title: p.agentName,
                status: .done,
                priority: nil,
                notes: nil,
                linkedFiles: [],
                conversationId: convId
            )
        }
    }

    private func handleTaskFailed(_ p: TaskFailedPayload) {
        let errorLine = "\n[Task \(p.taskId) failed: \(p.error)]"
        appendToAssistantMessage(errorLine)
    }

    // MARK: - Streaming Events

    private func handleTextDelta(_ p: TextDeltaPayload) {
        let current = accumulatedText[p.taskId, default: ""]
        accumulatedText[p.taskId] = current + p.delta

        let fullText = accumulatedText.values.joined()
        chatStore?.updateLastAssistantMessage(
            content: fullText,
            in: conversationId,
            persistImmediately: false
        )
    }

    private func handleTextReplace(_ p: TextReplacePayload) {
        accumulatedText[p.taskId] = p.replacement

        let fullText = accumulatedText.values.joined()
        chatStore?.updateLastAssistantMessage(
            content: fullText,
            in: conversationId,
            persistImmediately: false
        )
    }

    // MARK: - Patch & Rollback

    private func handlePatchApplied(_ p: PatchAppliedPayload) {
        let fileList = p.touchedFiles.prefix(5).joined(separator: ", ")
        let suffix = p.touchedFiles.count > 5
            ? " (+\(p.touchedFiles.count - 5) more)" : ""
        let riskLabel = p.riskScore > 0.7 ? " [HIGH RISK]" : ""
        let msg = "\nPatch applied: \(fileList)\(suffix)\(riskLabel)"
        appendToAssistantMessage(msg)
    }

    private func handleRollback(_ p: RollbackPayload) {
        let msg = "\n[Rollback triggered for task \(p.taskId): \(p.reason)]"
        appendToAssistantMessage(msg)
    }

    // MARK: - Review

    private func handleReviewFinding(_ p: ReviewFindingPayload) {
        let severity = p.finding.severity.rawValue.uppercased()
        let msg = "\n[\(severity)] \(p.finding.file): \(p.finding.message)"
        appendToAssistantMessage(msg)
    }

    // MARK: - Progress

    private func handleProgress(_ p: ProgressPayload) {
        completedTasks = p.completedTasks
        totalTasks = p.totalTasks
        jobState = p.currentState
    }

    // MARK: - Diagnostics

    private func handleCircuitBreaker(_ p: CircuitBreakerPayload) {
        circuitBreakerActive = (p.phase == .open)
        let msg = "\n[Circuit Breaker: \(p.phase.rawValue) — \(p.reason)]"
        appendToAssistantMessage(msg)
    }

    private func handleBackpressure(_ p: BackpressurePayload) {
        let status = p.active ? "active" : "cleared"
        chatStore?.setTaskStatus(
            "Backpressure \(status) (\(p.activeWorkers)/\(p.maxWorkers) workers)",
            for: conversationId
        )
    }

    private func handleProviderHealth(_ p: ProviderHealthPayload) {
        if p.status == .unhealthy {
            let msg = "\n[Provider \(p.providerId) unhealthy]"
            appendToAssistantMessage(msg)
        }
    }

    private func handleErrorBudget(_ p: ErrorBudgetPayload) {
        let msg = "\n[Error budget low: \(p.failedPercent)%/\(p.maxPercent)%"
            + ", \(p.consecutiveFailures) consecutive failures]"
        appendToAssistantMessage(msg)
    }

    // MARK: - Helpers

    private func appendToAssistantMessage(_ text: String) {
        guard let convId = conversationId else { return }
        let current = accumulatedText.values.joined()
        chatStore?.updateLastAssistantMessage(
            content: current + text,
            in: convId
        )
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        let seconds = Double(ms) / 1000.0
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let minutes = Int(seconds) / 60
        let remaining = Int(seconds) % 60
        return "\(minutes)m \(remaining)s"
    }
}
