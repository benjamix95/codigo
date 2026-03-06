import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func executeSendMessageTurn(
        targetConversationId: UUID,
        assistantMessageId: UUID,
        effectiveRuntimeProvider: any LLMProvider,
        prompt: String,
        taskRequestLabel: String,
        shouldRunPlanInline: Bool,
        ctx: WorkspaceContext,
        attachmentsToSend: [LLMAttachment]?
    ) {
        // 5. Execute async stream
        let isPlanMultiTurnFlow = (coderMode == .plan || shouldRunPlanInline)
            && planFlowPhase == .analyzing
        launchRunTask(for: targetConversationId) {
            var traceOutcome: ToolTraceTurnOutcome = .success
            do {
                if isPlanMultiTurnFlow {
                    // Multi-turn forced sequential plan flow
                    try await runMultiTurnPlanFlow(
                        provider: effectiveRuntimeProvider,
                        ctx: ctx,
                        attachmentsToSend: attachmentsToSend,
                        conversationId: targetConversationId,
                        shouldRunPlanInline: shouldRunPlanInline
                    )
                    // Safety net: if the flow returned without advancing to a terminal
                    // state (e.g., early return from a conversation-ID guard), reset the
                    // phase so the user isn't permanently stuck.
                    // Exception: .questioning + .awaitingClarification is a legitimate
                    // pause — the user needs to answer before the flow continues.
                    await MainActor.run {
                        guard shouldMutatePlanState(
                            targetConversationId: targetConversationId,
                            currentConversationId: self.conversationId
                        ) else {
                            cleanupPlanFlowAfterConversationSwitch(targetConversationId: targetConversationId)
                            return
                        }
                        let isPausedForClarification: Bool = {
                            if case .awaitingClarification = planningState { return true }
                            return false
                        }()
                        switch planFlowPhase {
                        case .analyzing, .generating:
                            NSLog(
                                "[PlanFlow] Safety reset: planFlowPhase was still %@ after runMultiTurnPlanFlow returned",
                                String(describing: planFlowPhase)
                            )
                            planFlowPhase = .idle
                            planningState = .idle
                            clearPlanStreamingState()
                        case .questioning where !isPausedForClarification:
                            NSLog(
                                "[PlanFlow] Safety reset: planFlowPhase was .questioning without awaitingClarification"
                            )
                            planFlowPhase = .idle
                            planningState = .idle
                            clearPlanStreamingState()
                        default:
                            break
                        }
                    }
                } else if coderMode == .agent {
                    await MainActor.run {
                        let (job, tasks) = PipelineJobFactory.fromChatMessage(
                            prompt: prompt,
                            displayRequest: taskRequestLabel,
                            workspace: ctx.workspacePath.path,
                            providerId: effectiveRuntimeProvider.id
                        )
                        let adapter = AgentWorkerAdapter(
                            provider: effectiveRuntimeProvider,
                            context: ctx,
                            jobId: job.jobId
                        )
                        let runtimeProviderId = effectiveRuntimeProvider.id
                        pipelineIntegrationService.executeJob(
                            job,
                            tasks: tasks,
                            workerAdapter: adapter,
                            providerId: runtimeProviderId,
                            conversationId: targetConversationId,
                            assistantMessageId: assistantMessageId,
                            onCompletion: { ctx in
                                Task { @MainActor in
                                    let pipelineOutcome = toolTraceTurnOutcome(
                                        pipelineSuccess: ctx.success,
                                        pipelineWasCancelled: ctx.wasCancelled
                                    )
                                    self.finalizeToolTraceTurn(
                                        conversationId: targetConversationId,
                                        outcome: pipelineOutcome
                                    )
                                    self.snapshotSubagentCardsAndEndTask(
                                        conversationId: targetConversationId,
                                        outcome: pipelineOutcome,
                                        shouldEndTask: false
                                    )
                                }
                            },
                            rawEventHandler: { type, payload, providerId, convId in
                                self.handleRawStreamEvent(
                                    type: type,
                                    payload: payload,
                                    providerId: providerId,
                                    conversationId: convId,
                                    shouldApplyPipelineArtifacts: false
                                )
                            }
                        )
                    }
                    return
                } else {
                    await MainActor.run {
                        applyLegacyLifecycleEvent(
                            kind: .turnStarted,
                            conversationId: targetConversationId,
                            providerId: effectiveRuntimeProvider.id,
                            status: "streaming"
                        )
                    }
                    let streamResult = try await flowCoordinator.runStream(
                        provider: effectiveRuntimeProvider,
                        prompt: prompt,
                        context: ctx,
                        attachments: attachmentsToSend,
                        onText: { content in
                            applyStreamingUpdate(
                                content: content,
                                conversationId: targetConversationId
                            )
                        },
                        onRaw: { t, p, pid in
                            handleRawStreamEvent(
                                type: t,
                                payload: p,
                                providerId: pid,
                                conversationId: targetConversationId
                            )
                        },
                        onError: { content in
                            Task { @MainActor in
                                applyLegacyStreamSnapshot(
                                    content: content,
                                    conversationId: targetConversationId,
                                    providerId: effectiveRuntimeProvider.id
                                )
                            }
                        },
                        onSignal: nil
                    )

                    let finalizedResult = try await continueIfPrematureStub(
                        initial: streamResult,
                        provider: effectiveRuntimeProvider,
                        originalPrompt: prompt,
                        context: ctx,
                        conversationId: targetConversationId,
                        hideContentDuringPlanDiscovery: false
                    )

                    await handleStreamResult(
                        conversationId: targetConversationId,
                        fullText: finalizedResult,
                        shouldRunPlanInline: shouldRunPlanInline,
                        ctx: ctx,
                        attachmentsToSend: attachmentsToSend,
                        prompt: prompt
                    )
                }
            } catch {
                chatStore.setLastAssistantStreaming(false, in: targetConversationId)
                clearStreamingReasoning(for: targetConversationId)
                if isInterruptedStreamError(error) {
                    traceOutcome = .aborted
                    await MainActor.run {
                        applyFlowCoordinatorState(for: targetConversationId) { $0.interrupt() }
                    }
                } else {
                    traceOutcome = .failed
                    applyLegacyStreamSnapshot(
                        content: userFacingStreamError(error),
                        conversationId: targetConversationId,
                        providerId: effectiveRuntimeProvider.id
                    )
                    applyLegacyLifecycleEvent(
                        kind: .turnFailed,
                        conversationId: targetConversationId,
                        providerId: effectiveRuntimeProvider.id,
                        status: "failed",
                        detail: userFacingStreamError(error),
                        persistImmediately: true
                    )
                    await MainActor.run {
                        applyFlowCoordinatorState(for: targetConversationId) { $0.fail() }
                    }
                }
                // C1 fix: Reset plan flow phase on error to prevent permanent stuck state.
                // Also reset if conversation changed but phase is stuck in a progress state.
                await MainActor.run {
                    guard shouldMutatePlanState(
                        targetConversationId: targetConversationId,
                        currentConversationId: self.conversationId
                    ) else {
                        cleanupPlanFlowAfterConversationSwitch(targetConversationId: targetConversationId)
                        return
                    }
                    planFlowPhase = .idle
                    planningState = .idle
                    clearPlanStreamingState()
                }
            }
            finalizeToolTraceTurn(conversationId: targetConversationId, outcome: traceOutcome)
            snapshotSubagentCardsAndEndTask(
                conversationId: targetConversationId,
                outcome: traceOutcome
            )
        }
    }
}
