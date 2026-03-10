import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

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
        if forcePlanInline {
            // `/plan` should force the planning flow — panel opens after screening in Phase 0.
            planToggleEnabled = true
        }
        guard !text.isEmpty || !attachedComposerAttachments.isEmpty else { return }
        guard let targetConversationId = conversationId else {
            appendTechnicalErrorMessage(
                "[Error] No conversation selected. Create or select a thread and try again.",
                in: nil
            )
            return
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

        // Check rate limit before proceeding — show alert popup if at 100%
        if let rateLimitMsg = providerUsageStore.rateLimitAlertMessage(
            for: providerRegistry.selectedProviderId)
        {
            rateLimitAlertText = rateLimitMsg
            showRateLimitAlert = true
            return
        }

        if autoCodeReviewRequest.prefersCodeReviewRuntimeProvider {
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

            let userVisibleText = displayedInput
            let storedContent = userVisibleText.isEmpty
                ? (storedAttachments.isEmpty ? "Review request" : "[Attached files]")
                : userVisibleText
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
            return
        }

        // Opening the plan panel should not automatically activate planning.
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
            // Guard against launching a new plan flow while one is already in progress
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
            // Panel opens after Phase 0 screening in runMultiTurnPlanFlow — not here
        } else if planFlowPhase != .building {
            planFlowPhase = .idle
            planningState = .idle
            clearPlanStreamingState()
        }

        // 1. Resolve the runtime provider
        guard
            let runtimeProvider = resolveRuntimeProvider(
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

        // 2. Build workspace context & checkpoint
        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath,
            scopeMode: ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto
        )
        do {
            try createCheckpointBeforeTurn(conversationId: targetConversationId, workspaceContext: ctx)
        } catch {
            resetPlanFlowAfterPreflightFailureIfNeeded()
            appendTechnicalErrorMessage(
                "[Checkpoint error: \(error.localizedDescription)]",
                in: targetConversationId
            )
            return
        }

        // 3. Prepare messages in chat store
        let turnId = UUID()
        let attachmentBundle = buildAttachmentBundle(
            attachments: attachedComposerAttachments,
            workspaceURL: ctx.workspacePath,
            turnId: turnId,
            capabilities: effectiveRuntimeProvider.attachmentCapabilities
        )
        let imagePathsToStore = attachmentBundle.chat
            .filter { $0.kind == .image }
            .map(\.localPath)
        inputText = ""
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
        // Preserve manual todos across turns; for a new standard turn reset all agent todos,
        // including stale canonical plan tasks from previous plans/conversations.
        // During an active plan build, keep canonical todos so the build's todo
        // tracking isn't wiped by a concurrent user message.
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
        attachedComposerAttachments = []

        // 4. Build the prompt with mode-specific instructions
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
