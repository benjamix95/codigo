import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func runMultiTurnPlanFlow(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        attachmentsToSend: [LLMAttachment]?,
        conversationId: UUID,
        shouldRunPlanInline: Bool,
        fullTurnPromptForScreeningFallback: String,
        skipScreening: Bool = false
    ) async throws -> MultiTurnPlanFlowOutcome {
        if let outcome = try await runMultiTurnPlanFlowPhase0(
            provider: provider,
            ctx: ctx,
            attachmentsToSend: attachmentsToSend,
            conversationId: conversationId,
            shouldRunPlanInline: shouldRunPlanInline,
            fullTurnPromptForScreeningFallback: fullTurnPromptForScreeningFallback,
            skipScreening: skipScreening
        ) {
            return outcome
        }
        switch try await runMultiTurnPlanFlowPhase1(
            provider: provider,
            ctx: ctx,
            attachmentsToSend: attachmentsToSend,
            conversationId: conversationId,
            shouldRunPlanInline: shouldRunPlanInline
        ) {
        case .finished(let outcome):
            return outcome
        case .continuePhase2(let analysisText):
            return try await runMultiTurnPlanFlowPhase2(
                provider: provider,
                ctx: ctx,
                conversationId: conversationId,
                shouldRunPlanInline: shouldRunPlanInline,
                analysisText: analysisText
            )
        }
    }
}
