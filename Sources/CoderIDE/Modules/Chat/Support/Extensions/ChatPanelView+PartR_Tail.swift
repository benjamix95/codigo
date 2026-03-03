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
        chatStore.updateLastAssistantMessage(
            content: initialChatContent,
            in: streamConversationId,
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
                    chatStore.updateLastAssistantMessage(content: summaryContent, in: streamConversationId, persistImmediately: true)
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
                    chatStore.updateLastAssistantMessage(content: summaryContent, in: streamConversationId, persistImmediately: true)
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

    internal func appendTechnicalErrorMessage(_ message: String, in conversationId: UUID?) {
        let normalized = normalizeTechnicalErrorMessage(message)
        if let conversationId,
            let last = chatStore.conversation(for: conversationId)?.messages.last,
            last.role == .assistant,
            last.content == normalized
        {
            return
        }
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: normalized, isStreaming: false),
            to: conversationId
        )
    }

    internal func normalizeTechnicalErrorMessage(_ message: String) -> String {
        let raw = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return "[Error] Operation not completed. Try again."
        }
        let lower = raw.lowercased()
        if lower.contains("coderengine.coderengineerror error 0")
            || (lower.contains("operation couldn") && lower.contains("coderengine"))
        {
            return
                "[Runtime error] Operation not completed by CLI provider. Check authentication and usage limits, then try again."
        }
        return raw
    }

    internal func userFacingStreamError(_ error: Error) -> String {
        if isNetworkError(error) && !networkMonitor.isPathSatisfied {
            return "[Connection lost] The network connection was interrupted. Reconnecting…"
        }
        let detail = String(describing: error)
        let normalized = normalizeTechnicalErrorMessage(detail)
        if normalized == detail.trimmingCharacters(in: .whitespacesAndNewlines) {
            return "[Error] \(error.localizedDescription)"
        }
        return normalized
    }

    internal func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let networkCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorDataNotAllowed,
        ]
        if nsError.domain == NSURLErrorDomain && networkCodes.contains(nsError.code) {
            return true
        }
        let desc = String(describing: error).lowercased()
        return desc.contains("network connection was lost")
            || desc.contains("not connected to the internet")
            || desc.contains("the internet connection appears to be offline")
            || desc.contains("a data connection is not currently allowed")
    }

    internal func isInterruptedStreamError(_ error: Error) -> Bool {
        if Task.isCancelled { return true }
        if error is CancellationError { return true }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return true
        }

        if executionController.runState == .stopping {
            return true
        }

        let normalized = String(describing: error).lowercased()
        if normalized.contains("cancellationerror")
            || normalized.contains("cancelled")
            || normalized.contains("canceled")
        {
            return true
        }

        return false
    }

    internal func rewindConversation() {
        guard !isRewinding else { return }
        guard let convId = conversationId,
            let conv = chatStore.conversation(for: convId),
            let lastUserIndex = conv.messages.lastIndex(where: { $0.role == .user })
        else { return }
        let lastUserMessage = conv.messages[lastUserIndex]
        let checkpoint = chatStore.previousCheckpoint(conversationId: convId)
        isRewinding = true

        Task {
            await MainActor.run {
                if isLoadingForCurrentConversation {
                    switch coderMode {
                    case .codeReviewMultiSwarm:
                        executionController.terminate(scope: .review)
                    case .plan:
                        executionController.terminate(scope: .plan)
                    default:
                        executionController.terminate(scope: .agent)
                    }
                    flowCoordinator.interrupt()
                    finalizeToolTraceTurn(conversationId: convId, outcome: .aborted)
                    snapshotSubagentCardsAndEndTask(conversationId: convId)
                }
            }

            // Try file restore only if we have git snapshots; on error continue
            // with chat-only rewind anyway (always-available behavior).
            if let checkpoint {
                for state in checkpoint.gitStates {
                    do {
                        try checkpointGitStore.restoreSnapshot(
                            ref: state.gitSnapshotRef, gitRoot: state.gitRootPath)
                    } catch {
                        await MainActor.run {
                            appendTechnicalErrorMessage(
                                "[Partial file rewind] \(error.localizedDescription)",
                                in: convId
                            )
                        }
                    }
                }
            }

            await MainActor.run {
                var rewound: Bool
                if let checkpoint {
                    rewound = chatStore.rewindConversationState(
                        to: checkpoint.id, conversationId: convId)
                    if rewound {
                        // Make sure the user message is removed from the chat
                        // (it remains only in the input for editing).
                        rewound = chatStore.rewindConversationToMessageCount(
                            lastUserIndex, conversationId: convId)
                    }
                } else {
                    // Fallback without checkpoint: remove last user turn + response.
                    rewound = chatStore.rewindConversationToMessageCount(
                        lastUserIndex, conversationId: convId)
                }
                guard rewound else {
                    appendTechnicalErrorMessage(
                        "[Rewind error: unable to restore chat state.]", in: convId)
                    isRewinding = false
                    return
                }

                // Cursor-style: bring the last user prompt back into the composer for editing.
                let placeholderImageOnly = "[Attached files]"
                inputText =
                    (lastUserMessage.content == placeholderImageOnly) ? "" : lastUserMessage.content
                attachedComposerAttachments = composerAttachments(from: lastUserMessage)
                isInputFocused = true
                planningState = .idle
                planFlowPhase = .idle
                if shouldResetTaskActivityStoreBeforeStartingTurn(
                    activeTaskConversationIds: chatStore.activeTaskConversationIds,
                    targetConversationId: convId
                ) {
                    clearTaskActivityPipeline()
                }
                swarmProgressStore.clear()
                activeBuildPlanConversationId = nil
                activeBuildAgentConversationId = nil
                isRewinding = false
            }
        }
    }

    internal func composerAttachments(from message: ChatMessage) -> [ComposerAttachment] {
        let baseAttachments: [ChatAttachment]
        if let attachments = message.attachments, !attachments.isEmpty {
            baseAttachments = attachments
        } else if let imagePaths = message.imagePaths, !imagePaths.isEmpty {
            baseAttachments = imagePaths.map { path in
                ChatAttachment(
                    kind: .image,
                    originalName: URL(fileURLWithPath: path).lastPathComponent,
                    mimeType: nil,
                    localPath: path
                )
            }
        } else {
            return []
        }

        return baseAttachments.compactMap { item in
            let url = URL(fileURLWithPath: item.localPath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ComposerAttachment(
                kind: item.kind,
                url: url,
                originalName: item.originalName,
                mimeType: item.mimeType,
                sizeBytes: item.sizeBytes
            )
        }
    }

    internal func rewindToMessage(at messageIndex: Int, conversationId: UUID) {
        guard !isRewinding else { return }
        guard let conv = chatStore.conversation(for: conversationId),
            messageIndex < conv.messages.count,
            conv.messages[messageIndex].role == .user
        else { return }
        let userMessage = conv.messages[messageIndex]
        let checkpoint = chatStore.checkpoint(forMessageIndex: messageIndex, conversationId: conversationId)
        isRewinding = true

        Task {
            await MainActor.run {
                if isLoadingForCurrentConversation {
                    switch coderMode {
                    case .codeReviewMultiSwarm:
                        executionController.terminate(scope: .review)
                    case .plan:
                        executionController.terminate(scope: .plan)
                    default:
                        executionController.terminate(scope: .agent)
                    }
                    flowCoordinator.interrupt()
                    finalizeToolTraceTurn(conversationId: conversationId, outcome: .aborted)
                    snapshotSubagentCardsAndEndTask(conversationId: conversationId)
                }
            }

            if let checkpoint {
                for state in checkpoint.gitStates {
                    do {
                        try checkpointGitStore.restoreSnapshot(
                            ref: state.gitSnapshotRef, gitRoot: state.gitRootPath)
                    } catch {
                        await MainActor.run {
                            appendTechnicalErrorMessage(
                                "[Partial file rewind] \(error.localizedDescription)",
                                in: conversationId
                            )
                        }
                    }
                }
            }

            await MainActor.run {
                // Remove the user message from the chat (and everything after it) so it can be
                // edited in the input and resent without duplicates.
                let rewound = chatStore.rewindConversationToMessageCount(
                    messageIndex, conversationId: conversationId)
                guard rewound else {
                    appendTechnicalErrorMessage(
                        "[Rewind error: unable to restore chat state.]", in: conversationId)
                    isRewinding = false
                    return
                }

                let placeholderImageOnly = "[Attached files]"
                inputText =
                    (userMessage.content == placeholderImageOnly) ? "" : userMessage.content
                attachedComposerAttachments = composerAttachments(from: userMessage)
                isInputFocused = true
                planningState = .idle
                planFlowPhase = .idle
                if shouldResetTaskActivityStoreBeforeStartingTurn(
                    activeTaskConversationIds: chatStore.activeTaskConversationIds,
                    targetConversationId: conversationId
                ) {
                    clearTaskActivityPipeline()
                }
                swarmProgressStore.clear()
                activeBuildPlanConversationId = nil
                activeBuildAgentConversationId = nil
                isRewinding = false
            }
        }
    }

}
