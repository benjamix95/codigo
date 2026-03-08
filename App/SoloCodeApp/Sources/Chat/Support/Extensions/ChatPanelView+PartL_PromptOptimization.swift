import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func optimizeCurrentPrompt() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard let selectedProvider = providerRegistry.selectedProvider else { return }

        // Use lightweight provider (no tools/policy) when available — much faster for prompt optimization.
        // Fall back to full runtime provider if lightweight is not configured or not authenticated.
        let providerToUse: any LLMProvider
        if let providerId = providerRegistry.selectedProviderId,
           let lightweight = ProviderFactory.lightweightProvider(
               providerId: providerId,
               config: providerFactoryConfig(),
               executionController: executionController
           ),
           lightweight.isAuthenticated() {
            providerToUse = lightweight
        } else if let resolved = resolveRuntimeProvider(
            selectedProvider: selectedProvider,
            shouldRunPlanInline: false,
            forcePlanInline: false,
            preferCodeReviewRuntimeProvider: false
        ) {
            providerToUse = resolved
        } else {
            providerToUse = selectedProvider
        }

        isOptimizingPrompt = true
        promptOptimizerTask?.cancel()
        promptOptimizerTask = Task {
            defer { isOptimizingPrompt = false }
            do {
                let ctx = WorkspaceContext.minimal()
                let optimized = try await PromptOptimizerService.optimize(
                    prompt: prompt,
                    using: providerToUse,
                    context: ctx
                )
                guard !Task.isCancelled else { return }
                optimizedPromptResult = optimized
                showPromptOptimizerPopup = true
            } catch {
                guard !Task.isCancelled else { return }
                appendTechnicalErrorMessage("[Prompt Optimizer] \(error.localizedDescription)", in: conversationId)
            }
        }
    }

    // MARK: - Multi-Turn Plan Flow

}
