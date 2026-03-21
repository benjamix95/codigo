import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

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
        let fullLooksLikePlanPayload = looksLikePlanPayload(full)
        let shouldRoutePlanStreamToPanel = shouldRoutePlanStream(to: streamConversationId)
        let shouldHidePlanMarkdownForBuild =
            isBuildContext && shouldRoutePlanStreamToPanel
        let hasPlanContextForStreamConversation = hasActivePlanContext(for: streamConversationId)
        let shouldHidePlanMarkdown = shouldHidePlanMarkdownInChat(
            shouldRoutePlanStreamToPanel: shouldRoutePlanStreamToPanel,
            coderMode: coderMode,
            shouldRunPlanInline: shouldRunPlanInline,
            fullLooksLikePlanPayload: fullLooksLikePlanPayload,
            shouldHidePlanMarkdownForBuild: shouldHidePlanMarkdownForBuild,
            hasActivePlanContext: hasPlanContextForStreamConversation
        )
        if shouldHidePlanMarkdownForBuild,
           shouldAutoOpenPlanPanel(trigger: .flowStarted),
           !showPlanPanel
        {
            openPlanPanelForCurrentContext(
                preserveHistorySelection: false,
                source: .automaticFlow
            )
        }
        let initialChatContent = shouldHidePlanMarkdown
            ? "Processing plan output in Plan Panel..."
            : full
        await MainActor.run {
            applyMainChatUIStreamIntent(
                "stream_finish_success",
                conversationId: streamConversationId,
                providerId: resolvedTurnProviderId(for: streamConversationId),
                text: initialChatContent
            )
            clearStreamingReasoning(for: streamConversationId)
        }
        await trySummarizeIfNeeded(ctx: ctx)

        // After a turn that actually produced code edits (non-plan), ensure a review+test todo exists.
        let isPlanBuildContext = (planFlowPhase == .building || planFlowPhase == .readyToBuild)
        let reviewTodoTitle = "Code Review & Test"
        let currentAssistantMessageId = chatStore.conversation(for: streamConversationId)?
            .messages
            .last(where: { $0.role == .assistant })?
            .id
        let turnTraceEvents: [ToolTraceEvent] = {
            guard let currentAssistantMessageId else { return [] }
            return toolTraceStore.events(
                conversationId: streamConversationId,
                assistantMessageId: currentAssistantMessageId
            )
        }()
        if !isPlanBuildContext,
           traceEventsContainSuccessfulCodeEdits(turnTraceEvents)
        {
            let isInScope = todoConversationScopeFilter(
                todos: todoStore.todos,
                conversationId: streamConversationId
            )
            let hasActiveReviewTodo = todoStore.todos.contains {
                isInScope($0)
                    && normalizedTodoTitle($0.title) == normalizedTodoTitle(reviewTodoTitle)
                    && ($0.status == .pending || $0.status == .inProgress)
            }
            if !hasActiveReviewTodo {
                let linkedFiles = touchedFilePathsFromTraceEvents(
                    toolTraceStore.allEvents(conversationId: streamConversationId)
                )
                await MainActor.run {
                    todoStore.upsertFromAgent(
                        id: nil,
                        title: reviewTodoTitle,
                        status: .pending,
                        priority: .high,
                        notes: "Review all touched files and run tests",
                        activeForm: "Reviewing code and running tests",
                        linkedFiles: linkedFiles,
                        conversationId: streamConversationId
                    )
                }
            }
        }
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
