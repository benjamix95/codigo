import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func executeWithPlanChoice(
        _ choice: String,
        fromPlanConversationId explicitPlanConversationId: UUID? = nil,
        providerOverrideId: String? = nil,
        allowIdleRebuild: Bool = false
    ) {
        guard conversationId != nil else { return }
        let planConversationId = explicitPlanConversationId ?? conversationId
        let hasActiveBuildTask = activeBuildAgentConversationId.map { chatStore.isTaskActive(for: $0) } ?? false
        let canStartBuild = shouldAllowStartingPlanBuild(
            isLoadingCurrentConversation: isLoadingForCurrentConversation,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            hasActiveBuildTask: hasActiveBuildTask
        )
        guard canStartBuild else {
            if hasActiveBuildTask {
                let scopeText =
                    (activeBuildPlanConversationId == planConversationId)
                    ? ""
                    : " for another conversation"
                appendTechnicalErrorMessage(
                    "[Plan] A build is already running\(scopeText). Wait for completion before starting another build.",
                    in: conversationId
                )
            }
            return
        }
        if activeBuildPlanConversationId != nil, !hasActiveBuildTask {
            // Defensive cleanup for stale build IDs after interruptions.
            activeBuildPlanConversationId = nil
            activeBuildAgentConversationId = nil
        }
        guard canExecutePlanBuild(
            phase: planFlowPhase,
            choice: choice,
            allowIdleRebuild: allowIdleRebuild
        ) else {
            appendTechnicalErrorMessage(
                "[Plan] Build not available. Generate a valid plan first.",
                in: conversationId
            )
            return
        }
        let hasRequiredTodoHeader = PlanOptionsParser.hasRequiredTodoHeader(choice)
        let planTodos = PlanOptionsParser.extractTodosFromOptionText(choice)
        guard hasRequiredTodoHeader, !planTodos.isEmpty else {
            appendTechnicalErrorMessage(
                "[Plan] Build requires a todo checklist in the selected option.",
                in: conversationId
            )
            if !showPlanPanel {
                openPlanPanelForCurrentContext(
                    preserveHistorySelection: true,
                    source: .manualDeepLink
                )
            }
            return
        }
        let provider: any LLMProvider
        let normalizedOverride = providerOverrideId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let overrideId = normalizedOverride, !overrideId.isEmpty {
            guard isPlanExecutionProviderIdAllowed(overrideId) else {
                appendTechnicalErrorMessage(
                    "[Plan] Invalid provider (\(overrideId)).",
                    in: conversationId
                )
                return
            }
            guard isPlanBuildExecutionCapableProvider(overrideId, registry: providerRegistry) else {
                appendTechnicalErrorMessage(
                    "[Plan] Provider not execution-capable (\(overrideId)).",
                    in: conversationId
                )
                return
            }
            if let overrideProvider = providerRegistry.provider(for: overrideId) {
                if overrideProvider.isAuthenticated() {
                    provider = overrideProvider
                } else {
                    appendTechnicalErrorMessage(
                        "[Plan] Provider not authenticated (\(overrideProvider.displayName)). Using fallback.",
                        in: conversationId
                    )
                    guard let backendProvider = resolvePreferredRealProvider() else {
                        return
                    }
                    provider = backendProvider
                }
            } else {
                appendTechnicalErrorMessage(
                    "[Plan] Provider not available (\(overrideId)). Using fallback.",
                    in: conversationId
                )
                guard let backendProvider = resolvePreferredRealProvider() else {
                    return
                }
                provider = backendProvider
            }
        } else {
            guard let backendProvider = resolvePreferredRealProvider() else {
                return
            }
            provider = backendProvider
        }

        let currentConv = chatStore.conversation(for: conversationId)
        let contextId = currentConv?.contextId
        let contextFolderPath = currentConv?.contextFolderPath
        let agentConvId = chatStore.getOrCreateConversationForMode(
            contextId: contextId, contextFolderPath: contextFolderPath, mode: .agent)
        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath,
            scopeMode: ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto
        )

        do {
            try createCheckpointBeforeTurn(
                conversationId: agentConvId,
                workspaceContext: ctx,
                planConversationIdForSnapshot: planConversationId
            )
        } catch {
            appendTechnicalErrorMessage(
                "[Checkpoint error: \(error.localizedDescription)]", in: agentConvId)
            return
        }

        planningState = .idle
        planFlowPhase = .readyToBuild
        chatStore.choosePlanPath(choice, for: planConversationId)
        chatStore.setWalkthrough("", for: planConversationId)

        todoStore.upsertCanonicalPlanTodos(planTodos, conversationId: planConversationId)
        let canonicalTodos = todoStore.canonicalTodos(for: planConversationId)
        chatStore.syncPlanStepsFromCanonicalTodos(canonicalTodos, in: planConversationId)

        if let selected = planHistoryStore.selectedEntryId {
            planHistoryStore.updateChosenPath(id: selected, chosenPath: choice)
            planHistoryStore.markRebuilt(id: selected)
        }
        // Keep the user on the plan conversation — build progress is visible
        // in the plan panel's trace section. Only switch mode and phase.
        providerRegistry.selectedProviderId = provider.id
        coderMode = .agent
        planFlowPhase = .building
        activeBuildPlanConversationId = planConversationId
        activeBuildAgentConversationId = agentConvId

        let planBuildAssistantMessageId = UUID()
        chatStore.addMessage(
            ChatMessage(
                id: planBuildAssistantMessageId,
                role: .assistant,
                content: "",
                isStreaming: true
            ),
            to: agentConvId
        )
        suppressedEmptyBuildAssistantMessageIds.insert(planBuildAssistantMessageId)
        startToolTraceTurn(
            conversationId: agentConvId,
            assistantMessageId: planBuildAssistantMessageId,
            providerId: provider.id
        )
        chatStore.beginTask(conversationId: agentConvId)
        if shouldResetTaskActivityStoreBeforeStartingTurn(
            activeTaskConversationIds: chatStore.activeTaskConversationIds,
            targetConversationId: agentConvId
        ) {
            clearTaskActivityPipeline()
        }
        scheduleFallbackTurnStartEvent(conversationId: agentConvId, providerId: provider.id)

        let planExecutionWorkflow = """
            **FUNDAMENTAL RULE: The plan TODOs are your BIBLE. Follow them EXACTLY in the order listed.**

            **Todo Workflow (strict, no noise):**
            1. The canonical plan TODOs are IMMUTABLE: do NOT create new TODOs, do NOT modify titles, do NOT reorder. Execute EXACTLY those present in the given order.
            2. For each TODO: set status=in_progress BEFORE starting, then status=done AFTER completion. Use \(CoderIDEMarkers.todoWritePrefix) to update the status.
            3. Emit \(CoderIDEMarkers.showTaskPanel) only if useful to visualize a real multi-step execution. Never emit it as a placeholder.
            4. Do NOT skip any TODO. Do NOT proceed to the next TODO until the current one is done.
            5. If a TODO is blocked, explain why and try to resolve it before moving on.
            6. Before finishing: ALL canonical TODOs MUST be done. If any is not done, do NOT terminate.
            7. Do not repeat the plan in chat: execute, update status, provide minimal operational feedback.
            8. Do NOT post kickoff fillers like "starting build/execution": begin directly from concrete execution updates.
            """

        let executionPlanBase: String
        if let board = chatStore.planBoard(for: planConversationId), !board.goal.isEmpty {
            executionPlanBase = """
            **Objective:** \(board.goal)

            **Plan (selected option):**
            \(choice)
            """
        } else {
            executionPlanBase = "**Plan to implement:**\n\(choice)"
        }

        let prompt = buildPlanExecutionPrompt(
            workflowInstructions: planExecutionWorkflow,
            executionPlanBase: executionPlanBase,
            planTodos: planTodos,
            canonicalTodos: canonicalTodos
        ).prompt

        launchRunTask(for: agentConvId) {
            var traceOutcome: ToolTraceTurnOutcome = .success
            do {
                _ = try await flowCoordinator.runStream(
                    provider: provider,
                    prompt: prompt,
                    context: ctx,
                    attachments: nil,
                    onText: { content in
                        applyStreamingUpdate(content: content, conversationId: agentConvId)
                    },
                    onRaw: { t, p, pid in
                        handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: agentConvId)
                    },
                    onError: { content in
                        Task { @MainActor in
                            chatStore.updateLastAssistantMessage(content: content, in: agentConvId)
                        }
                    },
                    onSignal: nil
                )
                chatStore.setLastAssistantStreaming(false, in: agentConvId)
                clearStreamingReasoning(for: agentConvId)
                await MainActor.run {
                    if selectedConversationId == planConversationId || selectedConversationId == agentConvId {
                        planFlowPhase = .readyToBuild
                    } else if planFlowPhase == .building {
                        planFlowPhase = .idle
                    }
                }
            } catch {
                chatStore.setLastAssistantStreaming(false, in: agentConvId)
                clearStreamingReasoning(for: agentConvId)
                if isInterruptedStreamError(error) {
                    traceOutcome = .aborted
                    await MainActor.run {
                        applyFlowCoordinatorState(for: agentConvId) { $0.interrupt() }
                        if selectedConversationId == planConversationId || selectedConversationId == agentConvId {
                            planFlowPhase = .readyToBuild
                        } else if planFlowPhase == .building {
                            planFlowPhase = .idle
                        }
                    }
                } else {
                    traceOutcome = .failed
                    chatStore.updateLastAssistantMessage(
                        content: userFacingStreamError(error), in: agentConvId)
                    await MainActor.run {
                        applyFlowCoordinatorState(for: agentConvId) { $0.fail() }
                        if selectedConversationId == planConversationId || selectedConversationId == agentConvId {
                            planFlowPhase = .readyToBuild
                        } else if planFlowPhase == .building {
                            planFlowPhase = .idle
                        }
                    }
                }
            }
            finalizeToolTraceTurn(conversationId: agentConvId, outcome: traceOutcome)
            snapshotSubagentCardsAndEndTask(conversationId: agentConvId)
            await MainActor.run {
                chatStore.removeAssistantMessageIfEmpty(
                    messageId: planBuildAssistantMessageId,
                    in: agentConvId
                )
                suppressedEmptyBuildAssistantMessageIds.remove(planBuildAssistantMessageId)
                if traceOutcome == .success, let planConvId = activeBuildPlanConversationId {
                    let canonicalTodos = todoStore.canonicalTodos(for: planConvId)
                    let agentMessages: [ChatMessage] = {
                        guard let conversation = chatStore.conversation(for: agentConvId),
                              let buildStartIndex = conversation.messages.firstIndex(where: { $0.id == planBuildAssistantMessageId }) else {
                            return []
                        }
                        return conversation.messages[buildStartIndex...]
                            .filter { $0.role == .assistant }
                    }()
                    let traceEventsForWalkthrough = toolTraceStore.events(
                        conversationId: agentConvId,
                        assistantMessageId: planBuildAssistantMessageId
                    )
                    let walkthroughMd = buildWalkthroughMarkdown(
                        canonicalTodos: canonicalTodos,
                        planBoard: chatStore.planBoard(for: planConvId),
                        agentMessages: agentMessages,
                        traceEvents: traceEventsForWalkthrough
                    )
                    let reviewLinkedFiles = touchedFilePathsFromTraceEvents(traceEventsForWalkthrough)
                    chatStore.setWalkthrough(walkthroughMd, for: planConvId)

                    let doneCount = canonicalTodos.filter { $0.status == .done }.count
                    let totalCount = canonicalTodos.count
                    let goalText = chatStore.planBoard(for: planConvId)?.goal ?? "Plan"
                    let recap = doneCount == totalCount
                        ? "Build complete. All \(totalCount) steps done: \(goalText)"
                        : "Build finished. \(doneCount)/\(totalCount) steps completed: \(goalText)"
                    chatStore.addMessage(
                        ChatMessage(id: UUID(), role: .assistant, content: recap),
                        to: agentConvId
                    )

                    // Add a Code Review & Test todo after plan build completion
                    todoStore.upsertFromAgent(
                        id: nil,
                        title: "Code Review & Test",
                        status: .pending,
                        priority: .high,
                        notes: "Review changes and run tests",
                        activeForm: "Reviewing code and running tests",
                        linkedFiles: reviewLinkedFiles,
                        conversationId: planConvId
                    )
                } else if let planConvId = activeBuildPlanConversationId {
                    chatStore.setWalkthrough("", for: planConvId)
                }
                activeBuildPlanConversationId = nil
                activeBuildAgentConversationId = nil
            }
        }
    }

    // MARK: - Send Message
    // MARK: - Send Message (orchestrator)

    internal func quotedReplyText(for message: ChatMessage) -> String {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .components(separatedBy: .newlines)
            .map { line in
                let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized.isEmpty ? ">" : "> \(normalized)"
            }
            .joined(separator: "\n")
    }

    internal func beginReply(to message: ChatMessage) {
        let quoted = quotedReplyText(for: message)
        inputText = quoted.isEmpty ? "" : "\(quoted)\n\n"
        isInputFocused = true
    }

    internal func mapAttachmentKindToLLM(_ kind: ChatAttachmentKind) -> LLMAttachmentKind {
        switch kind {
        case .image: return .image
        case .document: return .document
        case .file: return .file
        }
    }

    internal func prepareRuntimeAttachmentURL(
        sourceURL: URL,
        workspaceURL: URL,
        turnId: UUID
    ) -> URL {
        let standardizedSource = sourceURL.standardizedFileURL
        let standardizedWorkspace = workspaceURL.standardizedFileURL
        if standardizedSource.path.hasPrefix(standardizedWorkspace.path) {
            return standardizedSource
        }

        let runtimeDir = standardizedWorkspace
            .appendingPathComponent(".codigo_attachments", isDirectory: true)
            .appendingPathComponent(turnId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)

        let ext = standardizedSource.pathExtension
        let baseName = standardizedSource.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "_")
            .prefix(40)
        let runtimeFileName = ext.isEmpty
            ? "\(UUID().uuidString)_\(baseName)"
            : "\(UUID().uuidString)_\(baseName).\(ext)"
        let runtimeURL = runtimeDir.appendingPathComponent(String(runtimeFileName))
        if !FileManager.default.fileExists(atPath: runtimeURL.path) {
            try? FileManager.default.copyItem(at: standardizedSource, to: runtimeURL)
        }
        return runtimeURL
    }

    internal func buildAttachmentBundle(
        attachments: [ComposerAttachment],
        workspaceURL: URL,
        turnId: UUID,
        capabilities: ProviderAttachmentCapabilities
    ) -> (chat: [ChatAttachment], llm: [LLMAttachment], fallbackPreamble: String) {
        guard !attachments.isEmpty else { return ([], [], "") }

        var chatAttachments: [ChatAttachment] = []
        var llmAttachments: [LLMAttachment] = []
        var fallbackLines: [String] = []

        for item in attachments {
            let runtimeURL = prepareRuntimeAttachmentURL(
                sourceURL: item.url,
                workspaceURL: workspaceURL,
                turnId: turnId
            )
            let chatAttachment = ChatAttachment(
                kind: item.kind,
                originalName: item.originalName,
                mimeType: item.mimeType,
                localPath: item.url.path,
                sizeBytes: item.sizeBytes
            )
            chatAttachments.append(chatAttachment)
            llmAttachments.append(
                LLMAttachment(
                    kind: mapAttachmentKindToLLM(item.kind),
                    url: runtimeURL,
                    mimeType: item.mimeType,
                    filename: item.originalName,
                    sizeBytes: item.sizeBytes
                )
            )

            let isNativeSupported: Bool
            switch item.kind {
            case .image:
                isNativeSupported = capabilities.nativeImage
            case .document:
                isNativeSupported = capabilities.nativeDocument
            case .file:
                isNativeSupported = capabilities.nativeFile
            }
            if !isNativeSupported {
                let sizeText = item.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "n/a"
                fallbackLines.append("- \(item.originalName) [\(item.kind.rawValue)] path=\(runtimeURL.path) size=\(sizeText)")
            }
        }

        let preamble: String
        if fallbackLines.isEmpty {
            preamble = ""
        } else {
            preamble = """
            ## Attachments available for this request
            The following files are NOT natively supported by the provider and are available via local path:
            \(fallbackLines.joined(separator: "\n"))

            Use file reading tools to analyze them if needed.
            """
        }

        return (chatAttachments, llmAttachments, preamble)
    }

    // MARK: - Prompt Optimization

}
