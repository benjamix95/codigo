import AppKit
import CoderEngine
import os
import SwiftUI
import UniformTypeIdentifiers

private let chatSendStreamLog = Logger(subsystem: "com.solocode.app", category: "ChatSendStream")

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
    // Only Codex CLI needs this routing because it doesn't separate them.
    if providerId == "claude-cli" { return false }
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
                    print("[ChatDebug] -> STANDARD mode path taken")
                    let rustAvailable = ReviewCoreBridge.isEnabled
                    if !rustAvailable {
                        print("[ChatDebug] Rust bridge unavailable — using Swift pipeline fallback for raw events")
                    }
                    // Rust UI projection is optional — the stream still works
                    // with the Swift fallback path in applyMainChatUIStreamIntent.
                    _ = await MainActor.run {
                        projectMainChatUISnapshot(conversationId: targetConversationId)
                    }
                    let streamResult = try await flowCoordinator.runStream(
                        provider: effectiveRuntimeProvider,
                        prompt: prompt,
                        context: ctx,
                        attachments: attachmentsToSend,
                        onText: { content in
                            let cleaned = ChatStore.stripCoderideMarkers(content, aggressive: true)
                            let shouldRouteToReasoning = shouldRouteStreamingTextToReasoning(
                                coderMode: coderMode,
                                hasOperationalActivityInTurn: hasOperationalActivityInCurrentTurn(
                                    conversationId: targetConversationId
                                ),
                                providerId: effectiveRuntimeProvider.id
                            )
                            if chatSendStreamLog.isEnabled(type: .debug) {
                                chatSendStreamLog.debug(
                                    "onText len=\(cleaned.count, privacy: .public) routeToReasoning=\(shouldRouteToReasoning, privacy: .public) coderMode=\(String(describing: coderMode), privacy: .public) preview=\(String(cleaned.prefix(80)), privacy: .public)"
                                )
                            }
                            if shouldRouteToReasoning {
                                applyStreamingReasoningSnapshot(
                                    cleaned,
                                    conversationId: targetConversationId
                                )
                            } else {
                                processInlinePolicyAckMarkers(
                                    in: content,
                                    providerId: effectiveRuntimeProvider.id,
                                    conversationId: targetConversationId
                                )
                                applyMainChatUIStreamIntent(
                                    "stream_replace_text",
                                    conversationId: targetConversationId,
                                    providerId: effectiveRuntimeProvider.id,
                                    text: cleaned
                                )
                            }
                        },
                        onRaw: { t, p, pid in
                            handleRawStreamEvent(
                                type: t,
                                payload: p,
                                providerId: pid,
                                conversationId: targetConversationId,
                                shouldApplyPipelineArtifacts: true,
                                shouldUpdateInlineReasoningVisuals: true
                            )
                            if rustAvailable {
                                applyMainChatUIStreamIntent(
                                    "stream_apply_raw_event",
                                    conversationId: targetConversationId,
                                    providerId: pid,
                                    payload: ["event_kind": t].merging(p) { _, new in new }
                                )
                            }
                        },
                        onError: { content in
                            Task { @MainActor in
                                applyMainChatUIStreamIntent(
                                    "stream_finish_failure",
                                    conversationId: targetConversationId,
                                    providerId: effectiveRuntimeProvider.id,
                                    text: content
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
