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
        applyLegacyStreamSnapshot(
            content: initialChatContent,
            conversationId: streamConversationId,
            providerId: providerRegistry.selectedProviderId ?? "unknown"
        )
        applyLegacyLifecycleEvent(
            kind: .turnCompleted,
            conversationId: streamConversationId,
            providerId: providerRegistry.selectedProviderId ?? "unknown",
            status: "completed",
            persistImmediately: true
        )
        chatStore.setLastAssistantStreaming(false, in: streamConversationId)
        clearStreamingReasoning(for: streamConversationId)
        await trySummarizeIfNeeded(ctx: ctx)

        // Handle plan options parsing (safety net — multi-turn flow handles its own classification)
        if (coderMode == .plan || shouldRunPlanInline)
            && planFlowPhase != .analyzing
            && planFlowPhase != .questioning
            && planFlowPhase != .generating
            && planFlowPhase != .building
        {
            let classification = PlanOutputClassifier.classify(
                fullText: full,
                current: planFlowPhase,
                coderMode: coderMode,
                shouldRunPlanInline: shouldRunPlanInline
            )
            if classification.isConfident, let classificationState = classification.planningState {
                await MainActor.run {
                    planFlowPhase = classification.nextPhase
                    // Only update planningState for non-idle classifications;
                    // idle means the classifier found a signal (e.g. "no questions needed")
                    // but doesn't need to change the planning state.
                    if classificationState != .idle {
                        planningState = classificationState
                    }
                }
                if case .awaitingClarification = classificationState {
                    let summaryContent = "Clarifications needed to proceed with the plan. Open the Planning panel to answer the questions."
                    applyLegacyStreamSnapshot(
                        content: summaryContent,
                        conversationId: streamConversationId,
                        providerId: providerRegistry.selectedProviderId ?? "unknown"
                    )
                    await MainActor.run {
                        if shouldAutoOpenPlanPanel(trigger: .awaitingClarification), !showPlanPanel {
                            openPlanPanelForCurrentContext(
                                preserveHistorySelection: false,
                                source: .automaticFlow
                            )
                        }
                    }
                }
                if case .awaitingChoice(_, let opts) = classificationState {
                    let board = PlanBoard.build(from: full, options: opts)
                    chatStore.setPlanBoard(board, for: streamConversationId)
                    let currentConv = chatStore.conversation(for: streamConversationId)
                    let parsedSummary = PlanOptionsParser.extractDisplaySummary(from: full)
                    let summaryContent = "Plan ready in Plan Panel: \(parsedSummary.title)"
                    applyLegacyStreamSnapshot(
                        content: summaryContent,
                        conversationId: streamConversationId,
                        providerId: providerRegistry.selectedProviderId ?? "unknown"
                    )
                    _ = planHistoryStore.createEntry(
                        conversationId: streamConversationId,
                        contextId: currentConv?.contextId,
                        contextFolderPath: currentConv?.contextFolderPath,
                        title: parsedSummary.title,
                        markdown: full,
                        options: opts,
                        chosenPath: board.chosenPath,
                        tags: [],
                        sourceMessageId: nil
                    )
                    inlinePlanSummaries.removeValue(forKey: streamConversationId)
                    if shouldRunPlanInline {
                        let contextId = currentConv?.contextId
                        let contextFolderPath = currentConv?.contextFolderPath
                        let planConvId = chatStore.getOrCreateConversationForMode(
                            contextId: contextId, contextFolderPath: contextFolderPath,
                            mode: .plan)
                        chatStore.setPlanBoard(board, for: planConvId)
                    }
                    await MainActor.run {
                        if shouldAutoOpenPlanPanel(trigger: .awaitingChoice), !showPlanPanel {
                            openPlanPanelForCurrentContext(
                                preserveHistorySelection: false,
                                source: .automaticFlow
                            )
                        }
                    }
                }
            }
        }

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
