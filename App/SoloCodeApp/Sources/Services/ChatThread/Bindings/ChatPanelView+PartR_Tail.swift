import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func finalAssistantContentExcludingReasoning(
    fullText: String,
    reasoningText: String?
) -> String {
    let fullTrimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !fullTrimmed.isEmpty else { return "" }
    let reasoningTrimmed = (reasoningText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !reasoningTrimmed.isEmpty else { return fullTrimmed }

    if fullTrimmed == reasoningTrimmed {
        return ""
    }
    if fullTrimmed.hasPrefix(reasoningTrimmed) {
        let tail = String(fullTrimmed.dropFirst(reasoningTrimmed.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return tail
    }
    if reasoningTrimmed.contains(fullTrimmed) {
        return ""
    }
    return fullTrimmed
}

extension ChatPanelView {
    internal func handleStreamResult(
        conversationId streamConversationId: UUID,
        fullText: String,
        shouldRunPlanInline: Bool,
        ctx: WorkspaceContext,
        attachmentsToSend: [LLMAttachment]?,
        prompt: String
    ) async {
        let isBuildContext = isPlanBuildContext(
            conversationId: streamConversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
        let full = isBuildContext
            ? normalizeBuildFinalResponse(fullText)
            : fullText
        let shouldRoutePlanStreamToPanel = shouldRoutePlanStream(to: streamConversationId)
        let shouldHidePlanMarkdownForBuild =
            isBuildContext && shouldRoutePlanStreamToPanel
        let activeReasoningText = streaming.streamingReasoningConversationId == streamConversationId
            ? streaming.streamingReasoningText
            : chatStore.conversation(for: streamConversationId)?
                .messages
                .last(where: { $0.role == .assistant })?
                .reasoningText
        let shouldHidePlanMarkdown = planMarkdownHiddenInChat(
            effectiveFullText: full,
            conversationId: streamConversationId,
            isBuildContext: isBuildContext,
            shouldRunPlanInline: shouldRunPlanInline
        )
        if shouldHidePlanMarkdownForBuild,
           shouldAutoOpenPlanPanel(trigger: .flowStarted, planToggleEnabled: planToggleEnabled),
           !showPlanPanel
        {
            openPlanPanelForCurrentContext(
                preserveHistorySelection: false,
                source: .automaticFlow
            )
        }
        let finalVisibleChatContent = finalAssistantContentExcludingReasoning(
            fullText: full,
            reasoningText: activeReasoningText
        )
        await MainActor.run {
            applyMainChatUIStreamIntent(
                "stream_finish_success",
                conversationId: streamConversationId,
                providerId: resolvedTurnProviderId(for: streamConversationId),
                // Con plan nascosto in chat: non sovrascrivere il contenuto in store con un placeholder
                // (`apply_terminal_text_override`). La UI usa `shouldSuppressPlanArtifactsInChat` + placeholder.
                text: shouldHidePlanMarkdown ? nil : finalVisibleChatContent
            )
            clearStreamingReasoning(for: streamConversationId)
            syncAgentBackedPlanAfterStream(
                conversationId: streamConversationId,
                fullText: full,
                shouldRunPlanInline: shouldRunPlanInline,
                isBuildContext: isBuildContext
            )
        }
        await trySummarizeIfNeeded(ctx: ctx)

    }

    internal func createCheckpointBeforeTurn(
        conversationId: UUID?,
        workspaceContext: WorkspaceContext,
        planConversationIdForSnapshot: UUID? = nil
    ) throws {
        guard let conversationId else { return }
        let pathStrings = workspaceContext.workspacePaths.map(\.path)
        do {
            let states = try checkpointGitStore.captureSnapshots(
                conversationId: conversationId, workspacePaths: pathStrings)
            chatStore.createCheckpoint(
                for: conversationId,
                gitStates: states,
                planConversationIdForSnapshot: planConversationIdForSnapshot
            )
        } catch {
            // Cursor-style fallback: valid chat checkpoint even outside a Git repository.
            if let gitError = error as? ConversationCheckpointGitStore.GitStoreError {
                switch gitError {
                case .notGitRepository:
                    chatStore.createCheckpoint(
                        for: conversationId,
                        gitStates: [],
                        planConversationIdForSnapshot: planConversationIdForSnapshot
                    )
                    return
                default:
                    throw error
                }
            }
            throw error
        }
    }
}
