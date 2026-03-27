import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

enum MainChatSendExecutionRoute {
    case planFlow
    case agentPipeline
    case standardStream
}

func shouldRouteStreamingTextToReasoning(
    coderMode: CoderMode,
    hasOperationalActivityInTurn: Bool,
    providerId: String = ""
) -> Bool {
    // Claude CLI already emits reasoning via separate `thinking` blocks.
    // Its text_delta IS the real response — never route it to reasoning.
    if providerId == "claude-cli" { return false }
    // Codex (presentation `.suppressed`): niente UI reasoning — il flusso testo va nella bolla principale.
    if ChatReasoningPresentationPolicy.shouldSuppressReasoningUI(
        messageProviderId: nil,
        fallbackTurnProviderId: providerId
    ) {
        return false
    }
    return coderMode == .agent
}

func resolveMainChatSendExecutionRoute(
    coderMode: CoderMode,
    isPlanMultiTurnFlow: Bool,
    usesRustTransport: Bool
) -> MainChatSendExecutionRoute {
    if isPlanMultiTurnFlow {
        return .planFlow
    }
    if coderMode == .agent && !usesRustTransport {
        return .agentPipeline
    }
    return .standardStream
}

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
            let executionRoute = resolveMainChatSendExecutionRoute(
                coderMode: coderMode,
                isPlanMultiTurnFlow: isPlanMultiTurnFlow,
                usesRustTransport: effectiveRuntimeProvider is MainChatRustTransportProvider
            )
            print(
                "[ChatDebug] executeSendMessageTurn: coderMode=\(String(describing: self.coderMode)) isPlan=\(isPlanMultiTurnFlow ? 1 : 0) provider=\(effectiveRuntimeProvider.id)"
            )
            do {
                switch executionRoute {
                case .planFlow:
                    // Multi-turn forced sequential plan flow
                    let planOutcome = try await runMultiTurnPlanFlow(
                        provider: effectiveRuntimeProvider,
                        ctx: ctx,
                        attachmentsToSend: attachmentsToSend,
                        conversationId: targetConversationId,
                        shouldRunPlanInline: shouldRunPlanInline,
                        fullTurnPromptForScreeningFallback: prompt
                    )
                    if case let .continueWithDirectChat(fallbackPrompt, fallbackAttachments) = planOutcome {
                        try await runStandardMainChatSendStream(
                            targetConversationId: targetConversationId,
                            effectiveRuntimeProvider: effectiveRuntimeProvider,
                            prompt: fallbackPrompt,
                            shouldRunPlanInline: shouldRunPlanInline,
                            ctx: ctx,
                            attachmentsToSend: fallbackAttachments
                        )
                    }
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
                            print("[PlanFlow] Safety reset: planFlowPhase was still \(String(describing: planFlowPhase)) after runMultiTurnPlanFlow returned")
                            planFlowPhase = .idle
                            planningState = .idle
                            planClarificationQuestionnaire = nil
                            clearPlanStreamingState()
                        case .questioning where !isPausedForClarification:
                            print("[PlanFlow] Safety reset: planFlowPhase was .questioning without awaitingClarification")
                            planFlowPhase = .idle
                            planningState = .idle
                            planClarificationQuestionnaire = nil
                            clearPlanStreamingState()
                        default:
                            break
                        }
                    }
                case .agentPipeline:
                    print("[ChatDebug] -> AGENT fallback path taken (Swift provider pipeline)")
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
                case .standardStream:
                    // Both .agent and other modes use the same linear stream
                    // flow only when the main-chat transport is backed by the
                    // Rust runtime.
                    try await runStandardMainChatSendStream(
                        targetConversationId: targetConversationId,
                        effectiveRuntimeProvider: effectiveRuntimeProvider,
                        prompt: prompt,
                        shouldRunPlanInline: shouldRunPlanInline,
                        ctx: ctx,
                        attachmentsToSend: attachmentsToSend
                    )
                }
            } catch {
                if isInterruptedStreamError(error) {
                    traceOutcome = .aborted
                    await MainActor.run {
                        applyMainChatUIStreamIntent(
                            "stream_interrupt",
                            conversationId: targetConversationId,
                            providerId: effectiveRuntimeProvider.id,
                            text: nil
                        )
                        clearStreamingReasoning(for: targetConversationId)
                    }
                    await MainActor.run {
                        applyFlowCoordinatorState(for: targetConversationId) { $0.interrupt() }
                    }
                } else {
                    traceOutcome = .failed
                    await MainActor.run {
                        applyMainChatUIStreamIntent(
                            "stream_finish_failure",
                            conversationId: targetConversationId,
                            providerId: effectiveRuntimeProvider.id,
                            text: shouldPreservePartialAssistantContent(after: error)
                                ? nil
                                : userFacingStreamError(error)
                        )
                        clearStreamingReasoning(for: targetConversationId)
                    }
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
                    planClarificationQuestionnaire = nil
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
