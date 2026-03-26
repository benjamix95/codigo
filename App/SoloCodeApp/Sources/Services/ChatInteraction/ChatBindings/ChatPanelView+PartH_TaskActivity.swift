import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

private let composerTodoRetentionGraceIntervalSeconds: CFAbsoluteTime = 0.75

func shouldHoldComposerTodoOverlay(
    incomingItems: [TodoItem],
    retainedItems: [TodoItem],
    isLoading: Bool,
    isStreaming: Bool,
    hasRecentNonEmptySnapshot: Bool
) -> Bool {
    !hasVisibleComposerTodoOverlay(items: incomingItems)
        && hasVisibleComposerTodoOverlay(items: retainedItems)
        && (isLoading || isStreaming || hasRecentNonEmptySnapshot)
}

func resolveEffectiveComposerTodoItems(
    incomingItems: [TodoItem],
    retainedItems: [TodoItem],
    isLoading: Bool,
    isStreaming: Bool,
    hasRecentNonEmptySnapshot: Bool
) -> [TodoItem] {
    if hasVisibleComposerTodoOverlay(items: incomingItems) {
        return incomingItems
    }
    if shouldHoldComposerTodoOverlay(
        incomingItems: incomingItems,
        retainedItems: retainedItems,
        isLoading: isLoading,
        isStreaming: isStreaming,
        hasRecentNonEmptySnapshot: hasRecentNonEmptySnapshot
    ) {
        return retainedItems
    }
    return []
}

@MainActor
func resolveComposerTodoItems(
    todoStore: TodoStore,
    conversationId: UUID?
) -> [TodoItem] {
    guard let conversationId else {
        return []
    }
    return todoStore.displayTodosForChat(for: conversationId)
}

extension ChatPanelView {
    private var composerTodoHasRecentNonEmptySnapshot: Bool {
        composerTodoLastNonEmptySnapshotAt > 0
            && (CFAbsoluteTimeGetCurrent() - composerTodoLastNonEmptySnapshotAt) < composerTodoRetentionGraceIntervalSeconds
    }

    private func composerTodoInputSignature(_ items: [TodoItem]) -> String {
        composerTodoAutoExpandSignature(items: items)
    }

    @MainActor
    private func scheduleComposerTodoGraceReevaluation() {
        composerTodoGraceTask?.cancel()
        let currentConversationId = conversationId
        let delayNs = UInt64(composerTodoRetentionGraceIntervalSeconds * 1_000_000_000)
        composerTodoGraceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            guard composerTodoRetentionConversationId == currentConversationId else { return }
            let latestIncoming = composerTodoItems
            syncComposerTodoRetention(with: latestIncoming)
            composerTodoGraceTask = nil
        }
    }

    @MainActor
    private func syncComposerTodoRetention(with incomingItems: [TodoItem]) {
        if composerTodoRetentionConversationId != conversationId {
            composerTodoGraceTask?.cancel()
            composerTodoGraceTask = nil
            composerRetainedTodoItems = []
            composerTodoLastNonEmptySnapshotAt = 0
            composerTodoRetentionConversationId = conversationId
        }

        let incomingHasOverlay = hasVisibleComposerTodoOverlay(items: incomingItems)
        if incomingHasOverlay {
            composerTodoGraceTask?.cancel()
            composerTodoGraceTask = nil
            composerRetainedTodoItems = incomingItems
            composerTodoLastNonEmptySnapshotAt = CFAbsoluteTimeGetCurrent()
            return
        }

        if shouldHoldComposerTodoOverlay(
            incomingItems: incomingItems,
            retainedItems: composerRetainedTodoItems,
            isLoading: isLoadingForCurrentConversation,
            isStreaming: composerTodoRetentionStreamingSignal,
            hasRecentNonEmptySnapshot: composerTodoHasRecentNonEmptySnapshot
        ) {
            scheduleComposerTodoGraceReevaluation()
            return
        }

        composerTodoGraceTask?.cancel()
        composerTodoGraceTask = nil
        composerRetainedTodoItems = []
        composerTodoLastNonEmptySnapshotAt = 0
    }

    private func effectiveComposerTodoItems(from incomingItems: [TodoItem]) -> [TodoItem] {
        resolveEffectiveComposerTodoItems(
            incomingItems: incomingItems,
            retainedItems: composerRetainedTodoItems,
            isLoading: isLoadingForCurrentConversation,
            isStreaming: composerTodoRetentionStreamingSignal,
            hasRecentNonEmptySnapshot: composerTodoHasRecentNonEmptySnapshot
        )
    }

    @MainActor
    private func syncComposerTodoOverlayExpansionState(with items: [TodoItem]) {
        let signature = composerTodoAutoExpandSignature(items: items)
        let hasOverlay = hasVisibleComposerTodoOverlay(items: items)

        guard hasOverlay else {
            composerTodoLastAutoExpandedSignature = ""
            composerTodoOverlayExpanded = false
            clearComposerTodoOverlayUserDismissedForSelection()
            return
        }

        guard signature != composerTodoLastAutoExpandedSignature else {
            if !composerTodoOverlayExpanded, let cid = conversationId {
                let userDismissedSig = composerTodoOverlayUserDismissedSignatureByConversation[cid]
                if userDismissedSig != signature {
                    composerTodoOverlayExpanded = true
                }
            }
            return
        }

        clearComposerTodoOverlayUserDismissedForSelection()
        composerTodoLastAutoExpandedSignature = signature
        composerTodoOverlayExpanded = true
    }

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
        if conversationRuntime.taskFlushTask != nil { return }
        conversationRuntime.taskFlushTask = Task { @MainActor in
            let delay = UInt64(taskActivityFlushInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { conversationRuntime.taskFlushTask = nil; return }
            conversationRuntime.taskFlushTask = nil
            flushPendingTaskActivities()
        }
    }

    @MainActor
    internal func flushPendingTaskActivities() {
        flushPendingTaskActivities(conversationId: nil)
    }

    @MainActor
    internal func flushPendingTaskActivities(conversationId targetConversationId: UUID?) {
        let backlogBefore = conversationRuntime.pendingTaskActivities.count + conversationRuntime.pendingInstantGreps.count
        guard backlogBefore > 0 else { return }
        logTaskBacklogIfNeeded(context: "flush_start")

        let activities: [TaskActivity]
        let greps: [InstantGrepResult]
        if let targetConversationId {
            activities = conversationRuntime.pendingTaskActivities.filter {
                canonicalConversationScopeValue(
                    $0.payload["conversation_id"] ?? $0.payload["conversationId"]
                ) == targetConversationId.uuidString.lowercased()
            }
            greps = conversationRuntime.pendingInstantGreps.filter { $0.conversationId == targetConversationId }
            conversationRuntime.pendingTaskActivities.removeAll {
                canonicalConversationScopeValue(
                    $0.payload["conversation_id"] ?? $0.payload["conversationId"]
                ) == targetConversationId.uuidString.lowercased()
            }
            conversationRuntime.pendingInstantGreps.removeAll { $0.conversationId == targetConversationId }
        } else {
            activities = conversationRuntime.pendingTaskActivities
            greps = conversationRuntime.pendingInstantGreps
            conversationRuntime.pendingTaskActivities.removeAll(keepingCapacity: true)
            conversationRuntime.pendingInstantGreps.removeAll(keepingCapacity: true)
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

        let backlogAfter = conversationRuntime.pendingTaskActivities.count + conversationRuntime.pendingInstantGreps.count
        if backlogAfter > 0 {
            logTaskBacklogIfNeeded(context: "flush_reschedule")
            scheduleTaskActivityFlush()
        }
    }

    @MainActor
    internal func logTaskBacklogIfNeeded(context: String) {
        let backlog = conversationRuntime.pendingTaskActivities.count + conversationRuntime.pendingInstantGreps.count
        guard backlog >= taskBacklogDiagnosticThreshold else { return }
        NSLog("[StreamDiag] task_backlog_high count=%d context=%@", backlog, context)
    }

    @MainActor
    internal func clearTaskActivityPipeline() {
        conversationRuntime.taskFlushTask?.cancel()
        conversationRuntime.taskFlushTask = nil
        conversationRuntime.pendingTaskActivities.removeAll(keepingCapacity: true)
        conversationRuntime.pendingInstantGreps.removeAll(keepingCapacity: true)
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

    // MARK: - Composer Todo Helpers

    private var composerTodoLatestAssistant: ChatMessage? {
        guard let cid = conversationId else { return nil }
        return chatStore.conversation(for: cid)?
            .messages
            .last(where: { $0.role == .assistant })
    }

    private var composerTodoFileChanges: [ToolTraceFileChange] {
        guard let cid = conversationId, let msg = composerTodoLatestAssistant else { return [] }
        let events = toolTraceStore.events(conversationId: cid, assistantMessageId: msg.id)
        return ToolTraceFileChangeMapper.collect(from: events)
    }

    private var composerTodoMicroStatus: String? {
        guard let cid = conversationId,
              let msg = composerTodoLatestAssistant,
              msg.isStreaming else { return nil }
        // Stesso valore del footer messaggio: snapshot live (evita desync con calcolo diretto).
        if snapshotIsLoading,
           msg.id == snapshotActiveAssistantMessageId,
           cid == messagesConversationSnapshot?.id {
            return snapshotStreamingDetailText
        }
        return streamingDetailText(for: msg, conversationId: cid)
    }

    private var composerTodoIsStreaming: Bool {
        (composerTodoLatestAssistant?.isStreaming ?? false) && isLoadingForCurrentConversation
    }

    /// Messaggio assistente ancora in streaming: i todo “incoming” possono sparire tra un chunk e l’altro.
    private var composerTodoRetentionStreamingSignal: Bool {
        composerTodoLatestAssistant?.isStreaming ?? false
    }

    private var composerTodoItems: [TodoItem] {
        resolveComposerTodoItems(
            todoStore: todoStore,
            conversationId: conversationId
        )
    }

    // MARK: - Composer
    @ViewBuilder
    internal var composerArea: some View {
        let incomingComposerTodoItems = composerTodoItems
        let stabilizedComposerTodoItems = effectiveComposerTodoItems(from: incomingComposerTodoItems)
        let resolvedComposerFileChanges = composerTodoFileChanges
        let resolvedComposerMicroStatus = composerTodoMicroStatus
        let resolvedComposerStreaming = composerTodoIsStreaming
        let planningNextMoveInteractive: Bool = {
            guard let cid = conversationId else { return false }
            let scoped = scopedTaskActivities(for: cid)
            let label = TaskActivityStore.streamingStatusText(
                isPaused: executionController.runState == .paused,
                activities: scoped
            )
            return label == "Planning next move" && isLoadingForCurrentConversation
        }()
        VStack(spacing: 0) {
            ChatComposerView(
                inputText: $composerState.inputText,
                attachedAttachments: $composerState.attachedComposerAttachments,
                isSelectingImage: $composerState.isSelectingImage,
                isComposerDropTargeted: $composerState.isComposerDropTargeted,
                isConvertingHeic: $composerState.isConvertingHeic,
                isInputFocused: $composerState.isInputFocused,
                isProviderReady: isProviderReady,
                isProjectContextAvailable: effectiveContext.hasContext,
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
                voiceTranscript: voiceInputController.transcript,
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
                isOptimizingPrompt: isOptimizingPrompt,
                topOverlay: hasVisibleComposerTodoOverlay(items: stabilizedComposerTodoItems)
                    ? AnyView(
                        ComposerTodoOverlayView(
                            items: stabilizedComposerTodoItems,
                            fileChanges: resolvedComposerFileChanges,
                            microStatusText: resolvedComposerMicroStatus,
                            isStreaming: resolvedComposerStreaming,
                            isIDEStyle: coderMode == .ide,
                            isExpanded: composerTodoOverlayExpandedBinding,
                            onReviewChanges: {
                                gitPanelStore.isOpen = true
                                gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
                            },
                            onUserExpandedAfterHeaderTap: { expanded in
                                if expanded {
                                    clearComposerTodoOverlayUserDismissedForSelection()
                                } else {
                                    setComposerTodoOverlayUserDismissedForSelection(
                                        signature: composerTodoAutoExpandSignature(items: stabilizedComposerTodoItems)
                                    )
                                }
                            },
                            isPlanningNextMoveInteractive: planningNextMoveInteractive,
                            onPlanningNextMoveTap: planningNextMoveInteractive
                                ? { performPlanningNextMoveUserAction() }
                                : nil
                        )
                    )
                    : nil
            )
        }
        .onAppear {
            syncComposerTodoRetention(with: incomingComposerTodoItems)
            syncComposerTodoOverlayExpansionState(with: stabilizedComposerTodoItems)
        }
        .onChange(of: composerTodoInputSignature(incomingComposerTodoItems)) { _ in
            syncComposerTodoRetention(with: incomingComposerTodoItems)
            syncComposerTodoOverlayExpansionState(with: effectiveComposerTodoItems(from: incomingComposerTodoItems))
        }
        .onChange(of: conversationId) { _ in
            syncComposerTodoRetention(with: incomingComposerTodoItems)
            syncComposerTodoOverlayExpansionState(with: effectiveComposerTodoItems(from: incomingComposerTodoItems))
        }
        .onDisappear {
            composerTodoGraceTask?.cancel()
            composerTodoGraceTask = nil
            composerTodoOverlayExpanded = false
            composerTodoLastAutoExpandedSignature = ""
            clearComposerTodoOverlayUserDismissedForSelection()
        }
        .frame(maxWidth: chatColumnMaxWidth)
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
        .alert("Rate Limit Reached", isPresented: $panelState.showRateLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rateLimitAlertText)
        }
        .alert("Nessun progetto aperto", isPresented: $panelState.showNoProjectOpenAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "Apri una cartella o un workspace dalla barra laterale prima di inviare un messaggio."
            )
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
            codexModelOverride: providerSettings.$codexModelOverride,
            codexReasoningEffort: providerSettings.$codexReasoningEffort,
            codexSandbox: providerSettings.$codexSandbox,
            geminiModelOverride: providerSettings.$geminiModelOverride,
            swarmOrchestrator: swarmReviewSettings.$swarmOrchestrator,
            taskPanelEnabled: uiSettings.$taskPanelEnabled,
            showSwarmHelp: $showSwarmHelp,
            inputText: $composerState.inputText,
            planModeBackend: uiSettings.$planModeBackend,
            swarmWorkerBackend: swarmReviewSettings.$swarmWorkerBackend,
            openaiModel: providerSettings.$openaiModel,
            claudeModel: providerSettings.$claudeModel,
            openrouterModel: providerSettings.$openrouterModel,
            kiloModel: providerSettings.$kiloModel,
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
            planToggleEnabled: $panelState.planToggleEnabled,
            debugToggleEnabled: $panelState.debugToggleEnabled,
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
            codexModelOverride: providerSettings.$codexModelOverride,
            codexReasoningEffort: providerSettings.$codexReasoningEffort,
            codexSandbox: providerSettings.$codexSandbox,
            geminiModelOverride: providerSettings.$geminiModelOverride,
            swarmOrchestrator: swarmReviewSettings.$swarmOrchestrator,
            taskPanelEnabled: uiSettings.$taskPanelEnabled,
            showSwarmHelp: $showSwarmHelp,
            inputText: $composerState.inputText,
            planModeBackend: uiSettings.$planModeBackend,
            swarmWorkerBackend: swarmReviewSettings.$swarmWorkerBackend,
            openaiModel: providerSettings.$openaiModel,
            claudeModel: providerSettings.$claudeModel,
            openrouterModel: providerSettings.$openrouterModel,
            kiloModel: providerSettings.$kiloModel,
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
            planToggleEnabled: $panelState.planToggleEnabled,
            debugToggleEnabled: $panelState.debugToggleEnabled,
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
            planModeBackend: uiSettings.planModeBackend,
            swarmWorkerBackend: swarmReviewSettings.swarmWorkerBackend,
            openaiModel: providerSettings.openaiModel,
            claudeModel: providerSettings.claudeModel,
            contextRefreshTick: streaming.streamContentVersion / 12
        )
        .frame(maxWidth: chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
    }

}
