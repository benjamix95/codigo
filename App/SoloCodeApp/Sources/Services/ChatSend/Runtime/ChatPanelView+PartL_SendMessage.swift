import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func resolveSendTargetConversation(
    currentConversationId: UUID?,
    effectiveContext: EffectiveContext,
    reusableConversationId: UUID?,
    createConversation: (UUID?, String?) -> UUID
) -> (conversationId: UUID, requiresSelectionUpdate: Bool) {
    if let currentConversationId {
        return (currentConversationId, false)
    }
    if let reusableConversationId {
        return (reusableConversationId, true)
    }
    let folderScope = effectiveContext.context.flatMap { $0.folderPaths.count > 1 ? $0.activeFolderPath : nil }
    return (createConversation(effectiveContext.contextId, folderScope), true)
}

extension ChatPanelView {
    internal func sendMessage(preferCodeReviewRuntimeProvider: Bool? = nil) {
        let parsedInput = parsePlanCommandInput(inputText)
        let autoCodeReviewRequest = resolvedAutoCodeReviewRequest(for: parsedInput.llmPromptInput)
        let text = applyComposerCodeReviewModesIfNeeded(to: autoCodeReviewRequest.prompt)
        let displayedInput = parsedInput.displayedInput
        let forcePlanInline = parsedInput.forcePlanInline
        let runtimeReviewPreference: Bool? = {
            if let preferCodeReviewRuntimeProvider {
                return preferCodeReviewRuntimeProvider
            }
            return autoCodeReviewRequest.prefersCodeReviewRuntimeProvider ? true : nil
        }()
        if forcePlanInline { planToggleEnabled = true }
        guard !text.isEmpty || !attachedComposerAttachments.isEmpty else {
            return
        }
        // Clear composer immediately for snappy feel
        let capturedAttachments = attachedComposerAttachments
        inputText = ""
        attachedComposerAttachments = []

        let reusableConversationId = chatStore.reusableEmptyConversation(
            contextId: effectiveContext.contextId,
            contextFolderPath: effectiveContext.context.flatMap {
                $0.folderPaths.count > 1 ? $0.activeFolderPath : nil
            }
        )?.id
        let targetResolution = resolveSendTargetConversation(
            currentConversationId: conversationId,
            effectiveContext: effectiveContext,
            reusableConversationId: reusableConversationId
        ) { contextId, folderPath in
            chatStore.createConversation(contextId: contextId, contextFolderPath: folderPath, mode: coderMode)
        }
        let targetConversationId = targetResolution.conversationId
        if targetResolution.requiresSelectionUpdate {
            selectedConversationId = targetConversationId
        }

        let targetConversation = chatStore.conversation(for: targetConversationId)
        if let missingBoundProviderId = ThreadProviderSelectionService.missingBoundProviderId(
            conversation: targetConversation,
            selectedProviderId: providerRegistry.selectedProviderId,
            registry: providerRegistry
        ) {
            appendTechnicalErrorMessage(
                "[Error] Thread vincolato al provider \(missingBoundProviderId) non configurato/disponibile. Riconfigura \(missingBoundProviderId) per continuare.",
                in: targetConversationId
            )
            return
        }

        guard let selectedProvider = providerRegistry.selectedProvider else {
            appendTechnicalErrorMessage(
                "[Error] No provider selected. Configure a provider in Settings.",
                in: targetConversationId
            )
            return
        }
        hasJustCompletedTask = false

        if let rateLimitMsg = providerUsageStore.rateLimitAlertMessage(
            for: providerRegistry.selectedProviderId)
        {
            rateLimitAlertText = rateLimitMsg
            showRateLimitAlert = true
            return
        }

        if handleAutoCodeReviewLaunchIfNeeded(
            autoCodeReviewRequest,
            displayedInput: displayedInput,
            targetConversationId: targetConversationId
        ) {
            return
        }

        let shouldRunPlanInline = resolveShouldRunPlanInline(
            forcePlanInline: forcePlanInline,
            coderMode: coderMode,
            planToggleEnabled: planToggleEnabled
        )
        let isPlanModeRequested = (coderMode == .plan || shouldRunPlanInline)
        func resetPlanFlowAfterPreflightFailureIfNeeded() {
            guard shouldResetPlanFlowAfterPreflightFailure(
                isPlanModeRequested: isPlanModeRequested,
                phase: planFlowPhase
            ) else {
                return
            }
            planFlowPhase = .idle
            planningState = .idle
            clearPlanStreamingState()
        }
        if isPlanModeRequested {
            switch planFlowPhase {
            case .analyzing, .questioning, .generating, .building:
                appendTechnicalErrorMessage(
                    "[Plan] A plan flow is already in progress. Please wait for it to finish or interrupt it first.",
                    in: targetConversationId
                )
                return
            default:
                break
            }
            planFlowPhase = .analyzing
            planningState = .idle
            planAnalysisContext = ""
            planUserRequest = String(text.prefix(16_000))
            planClarificationAnswers = ""
            planClarificationCycles = 0
            clearPlanStreamingState()
            planShouldRunInline = shouldRunPlanInline
        } else if planFlowPhase != .building {
            planFlowPhase = .idle
            planningState = .idle
            clearPlanStreamingState()
        }

        guard
            let runtimeProvider = resolveMainChatTransportProvider(
                selectedProvider: selectedProvider,
                shouldRunPlanInline: shouldRunPlanInline,
                forcePlanInline: forcePlanInline,
                preferCodeReviewRuntimeProvider: runtimeReviewPreference
            )
        else {
            resetPlanFlowAfterPreflightFailureIfNeeded()
            appendTechnicalErrorMessage(
                "[Error] Unable to resolve runtime provider for this mode.",
                in: targetConversationId
            )
            return
        }

        guard runtimeProvider.isAuthenticated() else {
            resetPlanFlowAfterPreflightFailureIfNeeded()
            let providerName = runtimeProvider.displayName
            appendTechnicalErrorMessage(
                "[Error] Provider \(providerName) not authenticated. \(providerNotReadyMessage)",
                in: targetConversationId
            )
            return
        }
        let effectiveRuntimeProvider: any LLMProvider = runtimeProvider
        ThreadProviderSelectionService.persistRuntimeProviderSelection(
            chatStore: chatStore,
            conversationId: targetConversationId,
            runtimeProviderId: effectiveRuntimeProvider.id
        )

        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath,
            scopeMode: ContextScopeMode(rawValue: uiSettings.contextScopeModeRaw) ?? .auto
        )
        let checkpointConvId = targetConversationId
        let checkpointCtx = ctx
        let checkpointPlanSnapshotId: UUID? = nil
        Task.detached { [checkpointGitStore = self.checkpointGitStore, chatStore = self.chatStore] in
            let pathStrings = checkpointCtx.workspacePaths.map(\.path)
            do {
                let states = try checkpointGitStore.captureSnapshots(
                    conversationId: checkpointConvId, workspacePaths: pathStrings)
                await MainActor.run {
                    chatStore.createCheckpoint(
                        for: checkpointConvId,
                        gitStates: states,
                        planConversationIdForSnapshot: checkpointPlanSnapshotId
                    )
                }
            } catch {
                if let gitError = error as? ConversationCheckpointGitStore.GitStoreError,
                   case .notGitRepository = gitError {
                    await MainActor.run {
                        chatStore.createCheckpoint(
                            for: checkpointConvId,
                            gitStates: [],
                            planConversationIdForSnapshot: checkpointPlanSnapshotId
                        )
                    }
                }
            }
        }

        let turnId = UUID()
        let attachmentBundle = buildAttachmentBundle(
            attachments: capturedAttachments,
            workspaceURL: ctx.workspacePath,
            turnId: turnId,
            capabilities: effectiveRuntimeProvider.attachmentCapabilities
        )
        let imagePathsToStore = attachmentBundle.chat
            .filter { $0.kind == .image }
            .map(\.localPath)
        let userVisibleText = displayedInput
        let contentToStore =
            userVisibleText.isEmpty ? (attachmentBundle.chat.isEmpty ? "" : "[Attached files]") : userVisibleText
        chatStore.addMessage(
            ChatMessage(
                role: .user, content: contentToStore, isStreaming: false,
                imagePaths: imagePathsToStore.isEmpty ? nil : imagePathsToStore,
                attachments: attachmentBundle.chat.isEmpty ? nil : attachmentBundle.chat
            ),
            to: targetConversationId
        )
        let standardAssistantMessageId = UUID()
        chatStore.addMessage(
            ChatMessage(
                id: standardAssistantMessageId,
                role: .assistant,
                content: "",
                isStreaming: true
            ),
            to: targetConversationId
        )
        startToolTraceTurn(
            conversationId: targetConversationId,
            assistantMessageId: standardAssistantMessageId,
            providerId: effectiveRuntimeProvider.id
        )
        if let conv = chatStore.conversation(for: targetConversationId), let ctxId = conv.contextId {
            projectContextStore.setLastActiveConversation(
                contextId: ctxId,
                folderPath: conv.contextFolderPath,
                conversationId: conv.id
            )
        }
        chatStore.beginTask(conversationId: targetConversationId)
        if shouldResetTaskActivityStoreBeforeStartingTurn(
            activeTaskConversationIds: chatStore.activeTaskConversationIds,
            targetConversationId: targetConversationId
        ) {
            clearTaskActivityPipeline()
        }
        let hasActivePlanBuildTask = activeBuildAgentConversationId.map {
            chatStore.isTaskActive(for: $0)
        } ?? false
        let hasResumablePlanState: Bool = {
            let scopedCanonicalTodos = todoStore.canonicalTodos(for: targetConversationId)
            guard !scopedCanonicalTodos.isEmpty else { return false }
            let hasBuildChoiceForConversation: Bool = {
                guard let chosen = chatStore.planBoard(for: targetConversationId)?
                    .chosenPath?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !chosen.isEmpty
                else {
                    return false
                }
                return PlanOptionsParser.hasRequiredTodoHeader(chosen)
                    && !PlanOptionsParser.extractTodosFromOptionText(chosen).isEmpty
            }()
            guard hasBuildChoiceForConversation else { return false }

            let doneCount = scopedCanonicalTodos.filter { $0.status == .done }.count
            let hasInProgress = scopedCanonicalTodos.contains { $0.status == .inProgress }
            return hasInProgress || (doneCount > 0 && doneCount < scopedCanonicalTodos.count)
        }()
        let shouldClearPlanCanonicalTodos = shouldClearPlanCanonicalTodosOnNewTurn(
            phase: planFlowPhase,
            hasActivePlanBuildTask: hasActivePlanBuildTask,
            hasResumablePlanState: hasResumablePlanState
        )
        todoStore.clearAgentTodos(
            conversationId: targetConversationId,
            includePlanCanonical: shouldClearPlanCanonicalTodos
        )
        scheduleFallbackTurnStartEvent(
            conversationId: targetConversationId,
            providerId: effectiveRuntimeProvider.id
        )
        swarmProgressStore.clear(conversationId: targetConversationId)

        let attachmentsToSend = attachmentBundle.llm.isEmpty ? nil : attachmentBundle.llm

        let basePrompt = buildPrompt(userText: text, shouldRunPlanInline: shouldRunPlanInline)
        let prompt = attachmentBundle.fallbackPreamble.isEmpty
            ? basePrompt
            : "\(attachmentBundle.fallbackPreamble)\n\n\(basePrompt)"

        executeSendMessageTurn(
            targetConversationId: targetConversationId,
            assistantMessageId: standardAssistantMessageId,
            effectiveRuntimeProvider: effectiveRuntimeProvider,
            prompt: prompt,
            taskRequestLabel: text.isEmpty ? contentToStore : text,
            shouldRunPlanInline: shouldRunPlanInline,
            ctx: ctx,
            attachmentsToSend: attachmentsToSend
        )
    }
}
