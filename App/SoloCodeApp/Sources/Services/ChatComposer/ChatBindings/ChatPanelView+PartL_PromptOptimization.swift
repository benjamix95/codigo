import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @discardableResult
    internal func handleAutoCodeReviewLaunchIfNeeded(
        _ autoCodeReviewRequest: AutoCodeReviewRequest,
        displayedInput: String,
        targetConversationId: UUID
    ) -> Bool {
        guard autoCodeReviewRequest.prefersCodeReviewRuntimeProvider else { return false }

        let storedAttachments = attachedComposerAttachments.map { attachment in
            ChatAttachment(
                kind: attachment.kind,
                originalName: attachment.originalName,
                mimeType: attachment.mimeType,
                localPath: attachment.url.path(percentEncoded: false),
                sizeBytes: attachment.sizeBytes
            )
        }
        let imagePaths = storedAttachments
            .filter { $0.kind == .image }
            .map(\.localPath)

        inputText = ""
        attachedComposerAttachments = []

        let storedContent = displayedInput.isEmpty
            ? (storedAttachments.isEmpty ? "Review request" : "[Attached files]")
            : displayedInput
        chatStore.addMessage(
            ChatMessage(
                role: .user,
                content: storedContent,
                isStreaming: false,
                imagePaths: imagePaths.isEmpty ? nil : imagePaths,
                attachments: storedAttachments.isEmpty ? nil : storedAttachments
            ),
            to: targetConversationId
        )

        if coderMode != .codeReviewMultiSwarm {
            selectMode(.codeReviewMultiSwarm)
        }
        launchCodeReviewPanelRequest(
            prompt: autoCodeReviewRequest.prompt,
            scope: autoCodeReviewRequest.scopeTarget ?? .uncommitted,
            modes: autoCodeReviewRequest.selectedModes,
            invocationLabel: "Findings-first review"
        )
        return true
    }

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
