import Foundation
import CoderEngine

extension ChatPanelView {
    internal func interruptTask(for targetConversationId: UUID?) {
        var didCancelTask = cancelRunTask(for: targetConversationId)
        if !didCancelTask, let target = targetConversationId,
           activeBuildPlanConversationId == target,
           let agentId = activeBuildAgentConversationId {
            didCancelTask = cancelRunTask(for: agentId)
        }
        if !didCancelTask {
            let scope = executionScopeForActiveTask()
            executionController.terminate(scope: scope)
        }
        applyFlowCoordinatorState(for: targetConversationId) { $0.interrupt() }
        taskFlushTask?.cancel()
        taskFlushTask = nil
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
            voiceInputController.start { transcript in
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    inputText = trimmed
                } else {
                    inputText = inputText + (inputText.hasSuffix(" ") ? "" : " ") + trimmed
                }
                isInputFocused = true
            }
        case .listening:
            voiceInputController.stop()
        case .requestingPermission, .transcribing:
            break
        }
    }
}
