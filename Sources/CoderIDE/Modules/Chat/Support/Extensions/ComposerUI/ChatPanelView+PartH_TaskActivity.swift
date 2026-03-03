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
            if t.contains("mcp") { return "Calling MCP tool" }
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
        taskFlushTask = Task {
            let delay = UInt64(taskActivityFlushInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                taskFlushTask = nil
                flushPendingTaskActivities()
            }
        }
    }

    @MainActor
    internal func flushPendingTaskActivities() {
        let backlogBefore = pendingTaskActivities.count + pendingInstantGreps.count
        guard backlogBefore > 0 else { return }
        logTaskBacklogIfNeeded(context: "flush_start")

        let activities = pendingTaskActivities
        let greps = pendingInstantGreps
        pendingTaskActivities.removeAll(keepingCapacity: true)
        pendingInstantGreps.removeAll(keepingCapacity: true)

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
                    taskActivityStore.appendOrMergeBatchEvent(activity)
                }
            } else {
                taskActivityStore.addActivity(activity)
            }
        }

        for grep in greps {
            taskActivityStore.addInstantGrep(grep)
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
        taskActivityStore.clear()
    }

    internal func activityWithConversationContext(
        _ activity: TaskActivity,
        conversationId: UUID?
    ) -> TaskActivity {
        guard let conversationId else { return activity }
        var payload = activity.payload
        if payload["conversation_id"] == nil {
            payload["conversation_id"] = conversationId.uuidString.lowercased()
        }
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
                inputText: $inputText,
                attachedAttachments: $attachedComposerAttachments,
                isSelectingImage: $isSelectingImage,
                isComposerDropTargeted: $isComposerDropTargeted,
                isConvertingHeic: $isConvertingHeic,
                isInputFocused: $isInputFocused,
                isProviderReady: isProviderReady,
                isLoading: isLoadingForCurrentConversation,
                planningState: planningState,
                runtimeRunState: executionController.runState,
                runtimeTaskStartDate: composerRuntimeStartDate,
                frozenTimerText: composerFrozenTimerText,
                frozenTimerDismissible: composerFrozenTimerDismissible,
                activeModeColor: activeModeColor,
                activeModeGradient: activeModeGradient,
                inputHint: inputHint,
                providerNotReadyMessage: providerNotReadyMessage,
                quickCommandPresets: composerQuickCommandPresets,
                showCodeReviewAutofixToggle: coderMode == .codeReviewMultiSwarm,
                showPlanRequestIndicator: showPlanRequestIndicator,
                controlsRow: AnyView(modeControlsRow),
                voiceState: voiceInputController.state,
                codeReviewAutofixEnabled: Binding(
                    get: { !codeReviewAnalysisOnly },
                    set: { enabled in
                        codeReviewAnalysisOnly = !enabled
                    }
                ),
                onSend: sendMessage,
                onApplyQuickCommand: { text in
                    inputText = text
                    isInputFocused = true
                },
                onInputTextChanged: { _ in },
                onRunQuickCommand: { text in
                    inputText = text
                    isInputFocused = true
                    sendMessage()
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
        .frame(maxWidth: chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .popover(isPresented: $showPromptOptimizerPopup, arrowEdge: .bottom) {
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
            inputText: $inputText,
            planModeBackend: $planModeBackend,
            swarmWorkerBackend: $swarmWorkerBackend,
            openaiModel: $openaiModel,
            claudeModel: $claudeModel,
            openrouterModel: $openrouterModel,
            codexModels: codexModels,
            geminiModels: geminiModels,
            onSyncCodexProvider: syncCodexProvider,
            onSyncClaudeProvider: syncClaudeProvider,
            onSyncGeminiProvider: syncGeminiProvider,
            onSyncSwarmProvider: syncSwarmProvider,
            onSyncPlanProvider: syncPlanProvider,
            onSyncOpenRouterProvider: syncOpenRouterProvider,
            onSyncToolRuntimePolicy: syncToolRuntimePolicy,
            onUserSelectedProvider: { suppressModeSyncForNextProviderChange = true },
            onDelegateToAgent: delegateToAgent,
            attachedImageURLs: attachedComposerAttachments
                .filter { $0.kind == .image }
                .map(\.url),
            planToggleEnabled: $planToggleEnabled,
            debugToggleEnabled: $debugToggleEnabled,
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
            )
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
