import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func continueIfPrematureStub(
        initial: String,
        provider: any LLMProvider,
        originalPrompt: String,
        context: WorkspaceContext,
        conversationId: UUID,
        hideContentDuringPlanDiscovery: Bool = false
    ) async throws -> String {
        var combinedText = initial
        let maxAutoContinuationRounds = 3
        var round = 0

        while round < maxAutoContinuationRounds {
            let runtimeSnapshot = flowCoordinator.prepareDirectStreamContinuation(
                originalPrompt: originalPrompt,
                currentText: combinedText
            )
            guard let continuationPrompt = runtimeSnapshot?.output?.followUpPrompt else {
                break
            }
            round += 1
            if let runtimeSnapshot {
                flowCoordinator.setDirectRuntimeSnapshot(runtimeSnapshot)
            }

            let prior = combinedText
            let followUp = try await flowCoordinator.runStream(
                provider: provider,
                prompt: continuationPrompt,
                context: context,
                attachments: nil,
                onText: { deltaFull in
                    let combined = prior + "\n" + deltaFull
                    let displayContent = hideContentDuringPlanDiscovery
                        ? "Planning in progress… Open the Planning panel to see the result."
                        : combined
                    let shouldSanitize = isPlanBuildContext(
                        conversationId: conversationId,
                        phase: planFlowPhase,
                        activeBuildPlanConversationId: activeBuildPlanConversationId,
                        activeBuildAgentConversationId: activeBuildAgentConversationId
                    )
                    let sanitizedContent = shouldSanitize
                        ? stripPlanCheckboxes(displayContent)
                        : displayContent
                    appendPlanStreamingContent(
                        sanitizedContent,
                        conversationId: conversationId
                    )
                    if shouldAutoOpenPlanPanel(trigger: .flowStarted, planToggleEnabled: planToggleEnabled), !showPlanPanel {
                        openPlanPanelForCurrentContext(
                            preserveHistorySelection: false,
                            source: .automaticFlow
                        )
                    }
                    applyLegacyStreamSnapshot(
                        content: sanitizedContent,
                        conversationId: conversationId,
                        providerId: resolvedTurnProviderId(for: conversationId)
                    )
                },
                onRaw: { t, p, pid in
                    handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
                },
                onError: { content in
                    DispatchQueue.main.async {
                        let combined = prior + "\n" + content
                        chatStore.updateLastAssistantMessage(content: combined, in: conversationId)
                    }
                },
                onSignal: nil
            )

            combinedText = prior + "\n" + followUp
        }

        return combinedText
    }
}
