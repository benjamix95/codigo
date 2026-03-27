import Foundation
import CoderEngine

extension ChatPanelView {
    internal func interruptTask(for targetConversationId: UUID?, source: String = "unknown") {
        // #region agent log
        RuntimeEvidenceDebugLog.append(
            hypothesisId: "H9",
            location: "interruptTask",
            message: "interrupt_requested",
            data: [
                "conversationId": targetConversationId?.uuidString ?? "nil",
                "runState": "\(executionController.runState)",
                "source": source,
                "endedByManualStop": "\(lastTaskEndedByManualStop)",
            ]
        )
        // #endregion
        let scope = executionScopeForActiveTask()

        // Cancel the pipeline & tool runtime BEFORE killing the OS process.
        // This triggers onTermination → cancelSessionBridge in Rust, setting
        // the cancelled flag so the Rust worker thread can exit its read loop
        // before the pipe is forcibly closed by process termination.
        let didCancelPipeline = pipelineIntegrationService.cancelCurrentJob(for: targetConversationId)
        var didCancelTask = didCancelPipeline || cancelRunTask(for: targetConversationId)
        if !didCancelTask, let target = targetConversationId,
           activeBuildPlanConversationId == target,
           let agentId = activeBuildAgentConversationId {
            didCancelTask =
                pipelineIntegrationService.cancelCurrentJob(for: agentId)
                || cancelRunTask(for: agentId)
        }

        // Now terminate the OS process as a fallback. The Rust worker has
        // already been notified via cancelSessionBridge and will exit its
        // read loop; terminate() ensures the child process is killed even
        // if the Rust side hasn't reacted yet.
        executionController.terminate(scope: scope)

        applyFlowCoordinatorState(for: targetConversationId) { $0.interrupt() }
        conversationRuntime.taskFlushTask?.cancel()
        conversationRuntime.taskFlushTask = nil
        flushPendingTaskActivities()
        if let cid = targetConversationId {
            let cur =
                chatStore.conversation(for: cid)?.messages.last(where: {
                    $0.role == .assistant
                })?.content ?? ""
            chatStore.updateLastAssistantMessage(
                content: cur.isEmpty
                    ? "[Interrupted by user]"
                    : cur + "\n\n[Interrupted by user]", in: cid)
            chatStore.setLastAssistantStreaming(false, in: cid)
            clearStreamingReasoning(for: cid)
        }
        finalizeToolTraceTurn(conversationId: targetConversationId, outcome: .aborted)
        if targetConversationId == conversationId {
            cancelFallbackTurnStartEvent()
        }
        snapshotSubagentCardsAndEndTask(conversationId: targetConversationId)
        if activeBuildPlanConversationId == targetConversationId {
            activeBuildPlanConversationId = nil
            activeBuildAgentConversationId = nil
        }
        if targetConversationId == conversationId {
            resetPlanFlowAfterInterruption()
        }
    }

    internal func resetPlanFlowAfterInterruption() {
        switch planFlowPhase {
        case .building:
            planFlowPhase = .readyToBuild
            clearPlanStreamingState()
        case .proposalReady:
            break
        case .analyzing, .questioning, .generating:
            planFlowPhase = .idle
            planningState = .idle
            clearPlanStreamingState()
        default:
            break
        }
    }

    internal func executionScopeForCurrentMode() -> ExecutionScope {
        switch coderMode {
        case .codeReviewMultiSwarm: return .review
        case .plan: return .plan
        default: return .agent
        }
    }

    internal func executionScopeForActiveTask() -> ExecutionScope {
        executionController.activeScope ?? executionScopeForCurrentMode()
    }

    internal func pauseOrResumeActiveTask() {
        let scope = executionScopeForActiveTask()
        let previousRunState = executionController.runState
        if previousRunState == .paused {
            executionController.resume(scope: scope)
            guard executionController.runState == .running else { return }
            taskActivityStore.markResumed()
            taskActivityStore.addActivity(
                TaskActivity(
                    type: "process_resumed",
                    title: "Process resumed",
                    detail: "Execution resumed by user",
                    payload: [:],
                    phase: .executing,
                    isRunning: true
                )
            )
            return
        }

        executionController.pause(scope: scope)
        guard executionController.runState == .paused else { return }
        taskActivityStore.markPaused()
        taskActivityStore.addActivity(
            TaskActivity(
                type: "process_paused",
                title: "Process paused",
                detail: "Execution paused by user",
                payload: [:],
                phase: .planning,
                isRunning: false
            )
        )
    }

    internal func handleVoiceAction() {
        if isLoadingForCurrentConversation {
            return
        }
        switch voiceInputController.state {
        case .idle, .failed:
            // Save pre-existing text so we can prepend it to live partial results.
            voicePrefixText = inputText
            voiceInputController.start { [self] _ in
                // Final transcript already written to inputText by the live observer;
                // just clean up voice state.
                voicePrefixText = nil
                isInputFocused = true
            }
        case .listening:
            voiceInputController.stop()
        case .requestingPermission, .transcribing:
            break
        }
    }
}
