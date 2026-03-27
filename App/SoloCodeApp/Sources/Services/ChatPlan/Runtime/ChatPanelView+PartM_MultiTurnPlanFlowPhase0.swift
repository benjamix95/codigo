import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    /// Fase 0 — screening. Ritorna non-`nil` se il flusso multi-turn deve fermarsi qui.
    internal func runMultiTurnPlanFlowPhase0(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        attachmentsToSend: [LLMAttachment]?,
        conversationId: UUID,
        shouldRunPlanInline: Bool,
        fullTurnPromptForScreeningFallback: String,
        skipScreening: Bool
    ) async throws -> MultiTurnPlanFlowOutcome? {
        // ========================
        // PHASE 0: Screening (internal; chat shows only neutral status)
        // ========================
        if !skipScreening {
            let screeningPrompt = await MainActor.run { () -> String in
                guard self.conversationId == conversationId else { return "" }
                return buildPhase0ScreeningPrompt(
                    userRequest: planUserRequest,
                    planIntentConversationId: conversationId
                )
            }
            guard !screeningPrompt.isEmpty else {
                await MainActor.run {
                    resetPlanFlowAfterAbortedPreflight(
                        targetConversationId: conversationId,
                        reason: "empty_screening_prompt_after_bridge"
                    )
                }
                return .completed
            }
            await MainActor.run {
                guard self.conversationId == conversationId else { return }
                chatStore.updateLastAssistantMessage(
                    content: "Starting codebase analysis...",
                    in: conversationId
                )
            }
            let screeningResult = try await flowCoordinator.runStream(
                provider: provider,
                prompt: screeningPrompt,
                context: ctx,
                attachments: attachmentsToSend,
                onText: { _ in },
                onRaw: { [self] t, p, pid in
                    handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
                },
                onError: { [self] content in
                    Task { @MainActor in
                        chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                    }
                },
                onSignal: nil
            )

            let screeningText = screeningResult.trimmingCharacters(in: .whitespacesAndNewlines)
            let screeningSnapshot = await MainActor.run { () -> MainChatRuntimeSnapshotBridge? in
                guard self.conversationId == conversationId else { return nil }
                return planRuntimeAction(
                    "plan_apply_screening_result",
                    text: screeningText,
                    shouldRunInline: shouldRunPlanInline,
                    planIntentConversationId: conversationId
                )
            }
            guard await MainActor.run(body: { self.conversationId == conversationId }) else {
                await MainActor.run {
                    cleanupPlanFlowAfterConversationSwitch(targetConversationId: conversationId)
                }
                return .completed
            }
            let screeningStatus = screeningSnapshot?.output?.chatContentOverride
                ?? "Starting codebase analysis..."
            let skipFullPipeline = screeningSnapshot?.output?.skipFullPlanPipeline == true
                || parsePlanScreeningDecision(from: screeningText) == .noPlanNeeded

            // #region agent log
            PlanFlowDebugNDJSONLog.append(
                hypothesisId: "D",
                location: "PartM_MultiTurnPlanFlowPhase0",
                message: "phase0_after_screening_stream",
                data: [
                    "screenLen": "\(screeningText.count)",
                    "skipFullPipeline": skipFullPipeline ? "1" : "0",
                    "rustSkip": (screeningSnapshot?.output?.skipFullPlanPipeline == true) ? "1" : "0",
                ]
            )
            // #endregion

            if skipFullPipeline {
                let rustFlag = screeningSnapshot?.output?.skipFullPlanPipeline == true
                let swiftParse = parsePlanScreeningDecision(from: screeningText) == .noPlanNeeded
                AgentDebugSessionNDJSONLog.append(
                    hypothesisId: "PLAN_SCREEN",
                    location: "ChatPanelView+PartM_MultiTurnPlanFlow.swift:screening",
                    message: "plan_pipeline_skipped_direct_chat",
                    data: [
                        "conversationId": conversationId.uuidString,
                        "rustSkipFullPlanPipeline": rustFlag ? "1" : "0",
                        "swiftNoPlanNeededParse": swiftParse ? "1" : "0",
                        "inline": shouldRunPlanInline ? "1" : "0",
                    ]
                )
                await MainActor.run {
                    guard self.conversationId == conversationId else { return }
                    chatStore.updateLastAssistantMessage(
                        content: screeningStatus,
                        in: conversationId,
                        persistImmediately: true
                    )
                    chatStore.setLastAssistantStreaming(true, in: conversationId)
                    planFlowPhase = .idle
                    planningState = .idle
                    clearPlanStreamingState()
                    _ = planRuntimeAction(
                        "plan_reset",
                        shouldRunInline: shouldRunPlanInline,
                        planIntentConversationId: conversationId
                    )
                }
                return .continueWithDirectChat(
                    prompt: fullTurnPromptForScreeningFallback,
                    attachments: attachmentsToSend
                )
            }

            // Finalize screening in chat and open plan panel
            await MainActor.run {
                guard self.conversationId == conversationId else { return }
                chatStore.updateLastAssistantMessage(
                    content: screeningStatus,
                    in: conversationId,
                    persistImmediately: true
                )
                chatStore.setLastAssistantStreaming(false, in: conversationId)
                // Open the plan panel AFTER screening, BEFORE deep analysis
                if !showPlanPanel {
                    openPlanPanelForCurrentContext(
                        preserveHistorySelection: false,
                        source: .automaticFlow
                    )
                }
            }
        } else {
            // Screening was already done (auto-detect case) — just open the panel
            await MainActor.run {
                guard self.conversationId == conversationId else { return }
                if !showPlanPanel {
                    openPlanPanelForCurrentContext(
                        preserveHistorySelection: false,
                        source: .automaticFlow
                    )
                }
            }
        }
        return nil
    }
}
