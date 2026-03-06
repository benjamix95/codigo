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
        guard let currentConversationId = conversationId else { return }
        let planConversationId = explicitPlanConversationId ?? currentConversationId
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
                guard overrideProvider.isAuthenticated() else {
                    appendTechnicalErrorMessage(
                        "[Plan] Provider not authenticated (\(overrideProvider.displayName)). Authenticate this provider in Settings.",
                        in: conversationId
                    )
                    return
                }
                provider = overrideProvider
            } else {
                appendTechnicalErrorMessage(
                    "[Plan] Provider not available (\(overrideId)).",
                    in: conversationId
                )
                return
            }
        } else {
            guard let backendProvider = resolvePreferredRealProvider() else {
                return
            }
            provider = backendProvider
        }

        // Keep execution bound to the currently selected plan conversation.
        // Creating/reusing a detached agent thread causes trace/todo events
        // to appear outside the chat the user is actively using.
        let agentConvId = planConversationId
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

        todoStore.upsertCanonicalPlanTodos(planTodos, conversationId: planConversationId)
        let canonicalTodos = todoStore.prepareCanonicalPlanTodosForBuild(
            conversationId: planConversationId
        )
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

        executePlanBuildViaPipeline(
            provider: provider,
            ctx: ctx,
            planTodos: planTodos,
            agentConvId: agentConvId,
            planConversationId: planConversationId,
            planBuildAssistantMessageId: planBuildAssistantMessageId
        )
    }

    // MARK: - Pipeline Path

    private func executePlanBuildViaPipeline(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        planTodos: [String],
        agentConvId: UUID,
        planConversationId: UUID,
        planBuildAssistantMessageId: UUID
    ) {
        let todoItems = planTodos.map { PlanTodoItem(title: $0) }
        let workspace = ctx.workspacePath.path
        let (job, tasks) = PipelineJobFactory.fromPlanBuild(
            todos: todoItems,
            workspace: workspace,
            providerId: provider.id
        )
        let workerAdapter = AgentWorkerAdapter(
            provider: provider,
            context: ctx,
            jobId: job.jobId
        )

        pipelineIntegrationService.executeJob(
            job,
            tasks: tasks,
            workerAdapter: workerAdapter,
            providerId: provider.id,
            conversationId: agentConvId,
            assistantMessageId: planBuildAssistantMessageId,
            planConversationId: planConversationId,
            onCompletion: { ctx in
                Task { @MainActor in
                    let pipelineOutcome = toolTraceTurnOutcome(
                        pipelineSuccess: ctx.success,
                        pipelineWasCancelled: ctx.wasCancelled
                    )
                    self.finalizeToolTraceTurn(
                        conversationId: agentConvId,
                        outcome: pipelineOutcome
                    )
                    self.snapshotSubagentCardsAndEndTask(
                        conversationId: agentConvId,
                        outcome: pipelineOutcome,
                        shouldEndTask: false
                    )
                    self.activeBuildPlanConversationId = nil
                    self.activeBuildAgentConversationId = nil
                    if ctx.success {
                        self.planFlowPhase = .proposalReady
                    } else {
                        self.planFlowPhase = .readyToBuild
                    }
                }
            }
        )
    }

}
