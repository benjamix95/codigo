import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    /// Fase 1 — analisi codebase; o termina il flusso (anche dopo fase 3) oppure richiede fase 2.
    internal func runMultiTurnPlanFlowPhase1(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        attachmentsToSend: [LLMAttachment]?,
        conversationId: UUID,
        shouldRunPlanInline: Bool
    ) async throws -> MultiTurnPlanAfterPhase1 {
        // ========================
        // PHASE 1: Codebase Analysis
        // ========================
        let shouldStartPhase1 = await MainActor.run { () -> Bool in
            guard self.conversationId == conversationId else { return false }
            _ = planRuntimeAction(
                "plan_prepare_phase1_analysis_prompt",
                text: planUserRequest,
                shouldRunInline: shouldRunPlanInline,
                planIntentConversationId: conversationId
            )
            clearPlanStreamingState()
            return true
        }
        guard shouldStartPhase1 else {
            // Conversation changed before Phase 1 could start.
            await MainActor.run {
                cleanupPlanFlowAfterConversationSwitch(targetConversationId: conversationId)
            }
            return .finished(.completed)
        }

        let analysisPrompt = await MainActor.run { () -> String in
            guard self.conversationId == conversationId else { return "" }
            return buildPhase1AnalysisPrompt(
                userRequest: planUserRequest,
                planIntentConversationId: conversationId
            )
        }
        guard !analysisPrompt.isEmpty else {
            await MainActor.run {
                cleanupPlanFlowAfterConversationSwitch(targetConversationId: conversationId)
            }
            return .finished(.completed)
        }
        let analysisResult = try await flowCoordinator.runStream(
            provider: provider,
            prompt: analysisPrompt,
            context: ctx,
            attachments: attachmentsToSend,
            onText: { [self] content in
                updatePlanStreamingContent(content, conversationId: conversationId)
            },
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

        let analysisText = analysisResult.trimmingCharacters(in: .whitespacesAndNewlines)
        let analysisRuntimeSnapshot = await MainActor.run { () -> MainChatRuntimeSnapshotBridge? in
            guard self.conversationId == conversationId else { return nil }
            return planRuntimeAction(
                "plan_apply_analysis_result",
                text: analysisText,
                shouldRunInline: shouldRunPlanInline,
                planIntentConversationId: conversationId
            )
        }
        guard await MainActor.run(body: { self.conversationId == conversationId }) else {
            await MainActor.run {
                cleanupPlanFlowAfterConversationSwitch(targetConversationId: conversationId)
            }
            return .finished(.completed)
        }
        let shouldRequestClarifications = analysisRuntimeSnapshot?.plan?.phase == .questioning
        // MARK: Agent debug session 773578
        CursorDebugSession773578Log.append(
            hypothesisId: "H4",
            location: "ChatPanelView+PartM_MultiTurnPlanFlowPhase1",
            message: "phase1_after_analysis",
            data: [
                "shouldRequestClarifications": shouldRequestClarifications ? "1" : "0",
                "rustPlanPhase": analysisRuntimeSnapshot?.plan?.phase.map { String(describing: $0) } ?? "nil",
                "analysisLen": "\(analysisText.count)",
            ]
        )

        await MainActor.run {
            guard self.conversationId == conversationId else { return }
            updatePlanStreamingContent(analysisText, conversationId: conversationId)
            chatStore.updateLastAssistantMessage(
                content: analysisText,
                in: conversationId,
                persistImmediately: true
            )
            chatStore.setLastAssistantStreaming(false, in: conversationId)
            let transitionMessage = shouldRequestClarifications
                ? "Analysis complete. Checking if clarifications are needed..."
                : "Analysis complete. Generating definitive plan in the Plan Panel..."
            chatStore.addMessage(
                ChatMessage(id: UUID(), role: .assistant, content: transitionMessage),
                to: conversationId
            )
            // Panel is already opened in Phase 0 — no need to open here
        }

        if !shouldRequestClarifications {
            // Skip the question phase for well-scoped requests and continue directly.
            finalizeToolTraceTurn(conversationId: conversationId, outcome: .success)
            await MainActor.run {
                guard shouldMutatePlanState(
                    targetConversationId: conversationId,
                    currentConversationId: self.conversationId
                ) else { return }
                planningState = .idle
                clearPlanStreamingState()
            }
            try await runPlanFlowPhase3(
                provider: provider,
                ctx: ctx,
                conversationId: conversationId,
                shouldRunPlanInline: shouldRunPlanInline
            )
            return .finished(.completed)
        }
        return .continuePhase2(analysisText: analysisText)
    }
}
