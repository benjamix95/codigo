import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal static func immediateSubtitleLabel(for activity: TaskActivity) -> String {
        let t = activity.type.lowercased()
        if activity.isRunning {
            if t.contains("read") || t.contains("glob") { return "Reading files" }
            if t.contains("grep") || t.contains("search") { return "Searching codebase" }
            if t.contains("edit") || t.contains("write") || t.contains("file_change") { return "Editing code" }
            if t.contains("bash") || t.contains("command") { return "Running command" }
            if t.contains("mcp") { return userFacingToolName(from: activity.payload) }
            if t.contains("web_search") { return "Searching web" }
            if t.contains("web_fetch") { return "Fetching page" }
            if t.contains("agent") || t.contains("subagent") { return "Running subagent" }
            if t.hasPrefix("debug_") { return "Debugging" }
            if t.contains("todo") || t.contains("plan_step") { return "Planning next move" }
            return "Running"
        }
        return ""
    }

    @MainActor
    internal func scheduleTaskActivityFlush() {
        if taskFlushTask != nil { return }
        taskFlushTask = Task { @MainActor in
            let delay = UInt64(taskActivityFlushInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { taskFlushTask = nil; return }
            taskFlushTask = nil
            flushPendingTaskActivities()
        }
    }

    @MainActor
    internal func flushPendingTaskActivities() {
        flushPendingTaskActivities(conversationId: nil)
    }

    @MainActor
    internal func flushPendingTaskActivities(conversationId targetConversationId: UUID?) {
        let backlogBefore = pendingTaskActivities.count + pendingInstantGreps.count
        guard backlogBefore > 0 else { return }
        logTaskBacklogIfNeeded(context: "flush_start")

        let activities: [TaskActivity]
        let greps: [InstantGrepResult]
        if let targetConversationId {
            activities = pendingTaskActivities.filter {
                canonicalConversationScopeValue(
                    $0.payload["conversation_id"] ?? $0.payload["conversationId"]
                ) == targetConversationId.uuidString.lowercased()
            }
            greps = pendingInstantGreps.filter { $0.conversationId == targetConversationId }
            pendingTaskActivities.removeAll {
                canonicalConversationScopeValue(
                    $0.payload["conversation_id"] ?? $0.payload["conversationId"]
                ) == targetConversationId.uuidString.lowercased()
            }
            pendingInstantGreps.removeAll { $0.conversationId == targetConversationId }
        } else {
            activities = pendingTaskActivities
            greps = pendingInstantGreps
            pendingTaskActivities.removeAll(keepingCapacity: true)
            pendingInstantGreps.removeAll(keepingCapacity: true)
        }

        for activity in activities {
            if activity.type == "read_batch_started" || activity.type == "read_batch_completed"
                || activity.type == "web_search_started"
                || activity.type == "web_search_completed"
                || activity.type == "web_search_failed"
                || activity.type == "web_fetch_started"
                || activity.type == "web_fetch_completed"
                || activity.type == "web_fetch_failed"
                || activity.type == "command_execution"
                || activity.type == "bash" || activity.type == "mcp_tool_call"
                || activity.type == "skill_invocation"
            {
                if taskActivityStore.shouldPreserveSwarmCriticalEvent(activity) {
                    taskActivityStore.addActivity(activity)
                } else {
                    taskActivityStore.scheduleAppendOrMergeBatchEvent(activity)
                }
            } else {
                taskActivityStore.addActivity(activity)
            }
        }

        for grep in greps {
            taskActivityStore.scheduleAddInstantGrep(grep)
        }

        updateSidebarTaskStatus()

        let backlogAfter = pendingTaskActivities.count + pendingInstantGreps.count
        if backlogAfter > 0 {
            logTaskBacklogIfNeeded(context: "flush_reschedule")
            scheduleTaskActivityFlush()
        }
    }

    @MainActor
    internal func logTaskBacklogIfNeeded(context: String) {
        let backlog = pendingTaskActivities.count + pendingInstantGreps.count
        guard backlog >= taskBacklogDiagnosticThreshold else { return }
        NSLog("[StreamDiag] task_backlog_high count=%d context=%@", backlog, context)
    }

    @MainActor
    internal func clearTaskActivityPipeline() {
        taskFlushTask?.cancel()
        taskFlushTask = nil
        pendingTaskActivities.removeAll(keepingCapacity: true)
        pendingInstantGreps.removeAll(keepingCapacity: true)
        taskActivityStore.clear(preservingCodeReviewState: true)
    }

    internal func activityWithConversationContext(
        _ activity: TaskActivity,
        conversationId: UUID?
    ) -> TaskActivity {
        guard let conversationId else { return activity }
        let payload = payloadWithConversationScope(
            payload: activity.payload,
            conversationId: conversationId
        )
        return TaskActivity(
            id: activity.id,
            type: activity.type,
            title: activity.title,
            detail: activity.detail,
            payload: payload,
            timestamp: activity.timestamp,
            phase: activity.phase,
            isRunning: activity.isRunning,
            groupId: activity.groupId
        )
    }

    // MARK: - Composer
    @ViewBuilder
    internal var composerArea: some View {
        VStack(spacing: 0) {
            ChatComposerView(
                inputText: $composerState.inputText,
                attachedAttachments: $composerState.attachedAttachments,
                isSelectingImage: $composerState.isSelectingImage,
                isComposerDropTargeted: $composerState.isDropTargeted,
                isConvertingHeic: $composerState.isConvertingHeic,
                isInputFocused: $composerState.isInputFocused,
                isProviderReady: isProviderReady,
                isLoading: isLoadingForCurrentConversation,
                planningState: planningState,
                runtimeRunState: executionController.runState,
                runtimeTaskStartDate: composerRuntimeStartDate,
                frozenTimerText: composerFrozenTimerText,
                frozenTimerDismissible: composerFrozenTimerDismissible,
                isIDEStyle: coderMode == .ide,
                activeModeColor: activeModeColor,
                activeModeGradient: activeModeGradient,
                inputHint: inputHint,
                providerNotReadyMessage: providerNotReadyMessage,
                quickCommandPresets: composerQuickCommandPresets,
                slashCommandPresets: composerSlashCommandPresets,
                reviewModePresets: composerCodeReviewModePresets,
                showPlanRequestIndicator: showPlanRequestIndicator,
                controlsRow: AnyView(composerControlsRow),
                voiceState: voiceInputController.state,
                onSend: { handleComposerSend() },
                onApplyQuickCommand: { text in
                    handleComposerQuickCommand(text, runImmediately: false)
                },
                onToggleReviewMode: { modeId in
                    toggleComposerCodeReviewMode(modeId)
                },
                onInputTextChanged: { _ in },
                onRunQuickCommand: { text in
                    handleComposerQuickCommand(text, runImmediately: true)
                },
                onPauseResume: { pauseOrResumeActiveTask() },
                onStop: {
                    lastTaskEndedByManualStop = true
                    interruptTask()
                },
                onDismissFrozenTimer: { composerFrozenTimerState = nil },
                onVoiceAction: { handleVoiceAction() },
                onOptimizePrompt: { optimizeCurrentPrompt() },
                isOptimizingPrompt: isOptimizingPrompt
            )
        }
        .frame(maxWidth: coderMode == .ide ? 760 : chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, coderMode == .ide ? 14 : 20)
        .popover(isPresented: $composerState.showPromptOptimizerPopup, arrowEdge: .bottom) {
            PromptOptimizerPopup(
                originalPrompt: inputText,
                optimizedPrompt: optimizedPromptResult,
                onAccept: { accepted in
                    inputText = accepted
                    showPromptOptimizerPopup = false
                    isInputFocused = true
                },
                onCancel: {
                    showPromptOptimizerPopup = false
                }
            )
        }
        .alert("Rate Limit Reached", isPresented: $showRateLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rateLimitAlertText)
        }
    }

    internal var composerControlsRow: some View {
        coderMode == .ide ? AnyView(ideModeControlsRow) : AnyView(modeControlsRow)
    }

    @ViewBuilder
    internal var modeControlsRow: some View {
        ModeControlsBarView(
            providerRegistry: providerRegistry,
            chatStore: chatStore,
            coderMode: coderMode,
            conversationId: conversationId,
            isAnyAgentProviderReady: isAnyAgentProviderReady,
            codexModelOverride: $codexModelOverride,
            codexReasoningEffort: $codexReasoningEffort,
            codexSandbox: $codexSandbox,
            geminiModelOverride: $geminiModelOverride,
            swarmOrchestrator: $swarmOrchestrator,
            taskPanelEnabled: $taskPanelEnabled,
            showSwarmHelp: $showSwarmHelp,
            inputText: $composerState.inputText,
            planModeBackend: $planModeBackend,
            swarmWorkerBackend: $swarmWorkerBackend,
            openaiModel: $openaiModel,
            claudeModel: $claudeModel,
            openrouterModel: $openrouterModel,
            kiloModel: $kiloModel,
            codexModels: codexModels,
            geminiModels: geminiModels,
            onSyncCodexProvider: syncCodexProvider,
            onSyncClaudeProvider: syncClaudeProvider,
            onSyncGeminiProvider: syncGeminiProvider,
            onSyncSwarmProvider: syncSwarmProvider,
            onSyncPlanProvider: syncPlanProvider,
            onSyncOpenRouterProvider: syncOpenRouterProvider,
            onSyncKiloProvider: syncKiloProvider,
            onSyncToolRuntimePolicy: syncToolRuntimePolicy,
            onUserSelectedProvider: { suppressModeSyncForNextProviderChange = true },
            onDelegateToAgent: delegateToAgent,
            attachedImageURLs: attachedComposerAttachments
                .filter { $0.kind == .image }
                .map(\.url),
            planToggleEnabled: $planToggleEnabled,
            debugToggleEnabled: $debugUIState.toggleEnabled,
            swarmToggleEnabled: Binding(
                get: { showSwarmPanel },
                set: { newValue in
                    showSwarmPanel = newValue
                }
            ),
            codeReviewToggleEnabled: Binding(
                get: { showCodeReviewPanel },
                set: { newValue in
                    showCodeReviewPanel = newValue
                }
            ),
            browserToggleEnabled: Binding(
                get: { coderMode == .browser },
                set: { newValue in
                    if newValue {
                        selectMode(.browser)
                    } else if coderMode == .browser {
                        selectMode(.agent)
                    }
                }
            ),
            forcedTier: nil
        )
    }

    @ViewBuilder
    internal var ideModeControlsRow: some View {
        ModeControlsBarView(
            providerRegistry: providerRegistry,
            chatStore: chatStore,
            coderMode: coderMode,
            conversationId: conversationId,
            isAnyAgentProviderReady: isAnyAgentProviderReady,
            codexModelOverride: $codexModelOverride,
            codexReasoningEffort: $codexReasoningEffort,
            codexSandbox: $codexSandbox,
            geminiModelOverride: $geminiModelOverride,
            swarmOrchestrator: $swarmOrchestrator,
            taskPanelEnabled: $taskPanelEnabled,
            showSwarmHelp: $showSwarmHelp,
            inputText: $composerState.inputText,
            planModeBackend: $planModeBackend,
            swarmWorkerBackend: $swarmWorkerBackend,
            openaiModel: $openaiModel,
            claudeModel: $claudeModel,
            openrouterModel: $openrouterModel,
            kiloModel: $kiloModel,
            codexModels: codexModels,
            geminiModels: geminiModels,
            onSyncCodexProvider: syncCodexProvider,
            onSyncClaudeProvider: syncClaudeProvider,
            onSyncGeminiProvider: syncGeminiProvider,
            onSyncSwarmProvider: syncSwarmProvider,
            onSyncPlanProvider: syncPlanProvider,
            onSyncOpenRouterProvider: syncOpenRouterProvider,
            onSyncKiloProvider: syncKiloProvider,
            onSyncToolRuntimePolicy: syncToolRuntimePolicy,
            onUserSelectedProvider: { suppressModeSyncForNextProviderChange = true },
            onDelegateToAgent: delegateToAgent,
            attachedImageURLs: attachedComposerAttachments
                .filter { $0.kind == .image }
                .map(\.url),
            planToggleEnabled: $planToggleEnabled,
            debugToggleEnabled: $debugUIState.toggleEnabled,
            swarmToggleEnabled: Binding(
                get: { showSwarmPanel },
                set: { newValue in showSwarmPanel = newValue }
            ),
            codeReviewToggleEnabled: Binding(
                get: { showCodeReviewPanel },
                set: { newValue in showCodeReviewPanel = newValue }
            ),
            browserToggleEnabled: Binding(
                get: { coderMode == .browser },
                set: { newValue in
                    if newValue {
                        selectMode(.browser)
                    } else if coderMode == .browser {
                        selectMode(.agent)
                    }
                }
            ),
            forcedTier: .compact
        )
    }

    @ViewBuilder
    internal var usageFooterArea: some View {
        UsageFooterView(
            selectedConversationId: $selectedConversationId,
            effectiveContext: effectiveContext,
            planModeBackend: planModeBackend,
            swarmWorkerBackend: swarmWorkerBackend,
            openaiModel: openaiModel,
            claudeModel: claudeModel,
            contextRefreshTick: streamContentVersion / 12
        )
        .frame(maxWidth: chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
    }

}
