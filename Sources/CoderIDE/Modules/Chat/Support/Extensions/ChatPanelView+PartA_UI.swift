import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal var rootLayout: some View {
        HStack(spacing: 6) {
            VStack(spacing: 0) {
                // Keep out of macOS titlebar hit-test zone while still using full-height content.
                Color.clear
                    .frame(height: topInteractiveInset)
                    .allowsHitTesting(false)
                chatHeader

                ConnectionStatusBanner(monitor: networkMonitor)

                let scopedSwarmCards = taskActivityStore.swarmCardStates(for: conversationId)
                if coderMode == .agent
                    && (!swarmProgressStore.steps(for: conversationId).isEmpty
                        || !scopedSwarmCards.isEmpty)
                {
                    SwarmProgressView(
                        store: swarmProgressStore,
                        activities: scopedTaskActivities(for: conversationId),
                        conversationId: conversationId,
                        isTaskRunning: isLoadingForCurrentConversation,
                        onSelectSwarm: { swarmId in
                            showSwarmPanel = true
                            selectedSwarmId = swarmId
                        }
                    )
                }

                if showsSwarmViewOnly {
                    swarmDashboardArea
                } else {
                    messagesArea
                        .layoutPriority(1)
                }

                if shouldShowFinalChatActions {
                    finalChatActionsBar
                }

                // Keep the legacy task bar only when the composer is not visible (e.g. Swarm).
                if !shouldShowComposer(for: coderMode)
                    && (isLoadingForCurrentConversation
                        || isSummarizing
                        || pipelineIntegrationService.isRunning(for: conversationId))
                {
                    TaskControlBar(
                        chatStore: chatStore,
                        taskActivityStore: taskActivityStore,
                        executionController: executionController,
                        pipelineService: pipelineIntegrationService,
                        conversationId: conversationId,
                        coderMode: coderMode,
                        debugPhase: debugStore.phase,
                        isSummarizing: isSummarizing,
                        activeModeColor: activeModeColor,
                        onInterrupt: { interruptTask() }
                    )
                }

                if shouldShowComposer(for: coderMode) {
                    composerArea
                }
                if shouldShowUsageFooter(for: coderMode) {
                    usageFooterArea
                }
            }
            if showPlanPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(planPanelWidthStorage) }, set: { planPanelWidthStorage = Double($0) }),
                    minWidth: 220, maxWidth: 500, leadingEdge: true
                )
                planPanelSidebar
            }
            if showDebugPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(debugPanelWidthStorage) }, set: { debugPanelWidthStorage = Double($0) }),
                    minWidth: 240, maxWidth: 500, leadingEdge: true
                )
                debugPanelSidebar
            }
            if showSwarmPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(swarmPanelWidthStorage) }, set: { swarmPanelWidthStorage = Double($0) }),
                    minWidth: 260, maxWidth: 540, leadingEdge: true
                )
                swarmPanelSidebar
            }
            if showCodeReviewPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(codeReviewPanelWidthStorage) }, set: { codeReviewPanelWidthStorage = Double($0) }),
                    minWidth: 280, maxWidth: 560, leadingEdge: true
                )
                codeReviewPanelSidebar
            }
            if gitPanelStore.isOpen {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(gitPanelWidthStorage) }, set: { gitPanelWidthStorage = Double($0) }),
                    minWidth: 280, maxWidth: 500, leadingEdge: false
                )
                GitPanelView(
                    store: gitPanelStore,
                    effectiveContext: effectiveContext,
                    onOpenFile: { openFilesStore.openFile($0) }
                )
                .environmentObject(providerRegistry)
                .frame(width: CGFloat(gitPanelWidthStorage))
            }
        }
        .animation(.none, value: showPlanPanel)
        .animation(.none, value: showDebugPanel)
        .animation(.none, value: showSwarmPanel)
        .animation(.none, value: showCodeReviewPanel)
        .animation(.none, value: gitPanelStore.isOpen)
    }

    internal func applyProviderSelectionModifiers<Content: View>(to content: Content) -> some View {
        content
            .onChange(of: providerRegistry.selectedProviderId) { _, newId in
            if shouldSyncModeOnProviderChange(suppressForUserPicker: suppressModeSyncForNextProviderChange) {
                syncCoderModeToProvider(newId)
            } else {
                suppressModeSyncForNextProviderChange = false
            }
            checkProviderAuth()
        }
        .onChange(of: selectedConversationId) { oldId, newId in
            draftSaveTask?.cancel()
            draftSaveTask = nil
            persistThreadUIState(for: oldId)
            persistDebugState(for: oldId)
            pipelineIntegrationService.unregisterDebugStore(for: oldId)
            // Save draft text for the previous conversation.
            if let oldId {
                let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    chatStore.draftTexts.removeValue(forKey: oldId)
                } else {
                    chatStore.draftTexts[oldId] = inputText
                }
            }
            // Restore draft text for the new conversation (or clear).
            inputText = chatStore.draftTexts[newId ?? UUID()] ?? ""

            if ignoreNextConversationChangeReset {
                ignoreNextConversationChangeReset = false
            } else {
                userModeOverrideUntilConversationChange = false
            }
            // Allow the previous thread to keep running in the background —
            // don't nil out activeBuildPlanConversationId here so the
            // build completion handler can still finalize successfully.
            planHistoryStore.setSelectedEntry(id: nil)
            restoreDebugState(for: newId)
            applyPendingDebugEvents(for: newId)
            if let newId {
                bindRuntimeDebugProjection(for: newId)
            }
            // Clear per-turn activity data so the swarm panel doesn't show
            // activities from the previous conversation when reopened.
            taskActivityStore.clearSwarmCards(for: oldId)
            swarmProgressStore.clear(conversationId: oldId)
            syncProviderFromConversation()
            restorePlanStateIfNeeded(for: newId)
            restoreThreadUIState(for: newId)
            requestInitialComposerFocusIfNeeded()
        }
        .onAppear {
            migrateSwarmProviderDefaultsIfNeeded()
            syncProviderFromConversation()
            scheduleToolRuntimePolicySync(immediate: true)
            codexModels = CodexModelsCache.loadModels()
            geminiModels = GeminiModelsCache.loadModels()
            syncSwarmProvider()
            syncCodeReviewRuntimeConfig()
            syncPlanProvider()
            checkProviderAuth()
            gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
            restorePlanStateIfNeeded(for: selectedConversationId)
            restoreThreadUIState(for: selectedConversationId)
            wireTodoPlanBidirectionalSync()
            if let selectedConversationId {
                bindRuntimeDebugProjection(for: selectedConversationId)
            }
            requestInitialComposerFocusIfNeeded()
        }
    }

    internal func adjustWindowForPanelToggle(isOpening: Bool, width: CGFloat) {
        guard autoResizeSidePanels else { return }
        let delta = isOpening ? (width + 12) : -(width + 12)
        DispatchQueue.main.async {
            WindowResizeHelper.adjustWidth(by: delta, animate: false)
        }
    }

    internal func applyRuntimeLifecycleModifiers<Content: View>(to content: Content) -> some View {
        let lifecycleTracked = content
            .onChange(of: showSwarmPanel) { wasOpen, isShowing in
                if isShowing && !wasOpen {
                    adjustWindowForPanelToggle(isOpening: true, width: CGFloat(swarmPanelWidthStorage))
                } else if !isShowing && wasOpen {
                    adjustWindowForPanelToggle(isOpening: false, width: CGFloat(swarmPanelWidthStorage))
                    // Restore the plan panel if plan mode is still active
                    if planToggleEnabled && !showPlanPanel && !showDebugPanel {
                        showPlanPanel = true
                    }
                }
            }
            .onChange(of: showDebugPanel) { wasOpen, isShowing in
                if debugToggleEnabled != isShowing {
                    debugToggleEnabled = isShowing
                }
                if isShowing && showPlanPanel {
                    showPlanPanel = false
                    // Do NOT disable planToggleEnabled — user may return to plan later
                }
                if isShowing && coderMode != .debug {
                    selectMode(.debug)
                } else if !isShowing && coderMode == .debug && !debugStore.phase.isActive {
                    selectMode(.agent)
                }
                if isShowing && !wasOpen {
                    adjustWindowForPanelToggle(isOpening: true, width: CGFloat(debugPanelWidthStorage))
                } else if !isShowing && wasOpen {
                    adjustWindowForPanelToggle(isOpening: false, width: CGFloat(debugPanelWidthStorage))
                    // Restore the plan panel if plan mode is still active
                    if planToggleEnabled && !showPlanPanel {
                        showPlanPanel = true
                    }
                }
            }
            .onChange(of: debugToggleEnabled) { _, isEnabled in
                guard !isRestoringThreadUIState else { return }
                guard showDebugPanel != isEnabled else { return }
                showDebugPanel = isEnabled
            }
            // Auto-expand/shrink window when side panels open/close
            .onChange(of: showPlanPanel) { wasOpen, isOpen in
                if isOpen && showDebugPanel {
                    debugToggleEnabled = false
                    showDebugPanel = false
                }
                if isOpen && !wasOpen {
                    adjustWindowForPanelToggle(isOpening: true, width: CGFloat(planPanelWidthStorage))
                } else if !isOpen && wasOpen {
                    adjustWindowForPanelToggle(isOpening: false, width: CGFloat(planPanelWidthStorage))
                    if planPanelPresentationSource == .automaticFlow {
                        planPanelPresentationSource = .manualDeepLink
                    }
                }
                if isOpen {
                    planToggleEnabled = true
                } else if wasOpen,
                          !isPlanShortcutCycling,
                          shouldDisablePlanToggleWhenPanelCloses(
                            phase: planFlowPhase,
                            planningState: planningState,
                            coderMode: coderMode,
                            hasActiveBuildSession: activeBuildPlanConversationId != nil
                          )
                {
                    planToggleEnabled = false
                }
            }
            .onChange(of: planToggleEnabled) { _, isEnabled in
                guard !isRestoringThreadUIState else { return }
                // Keep planner panel visibility in sync with the composer inline-plan button.
                if isEnabled {
                    if !showPlanPanel && !isPlanShortcutCycling {
                        openPlanPanelForCurrentContext(source: .manualShortcut)
                    }
                } else if showPlanPanel && shouldAllowPlanToggleDeactivation(phase: planFlowPhase) {
                    showPlanPanel = false
                    planningState = .idle
                    planFlowPhase = .idle
                    clearPlanStreamingState()
                    planHistoryStore.setSelectedEntry(id: nil)
                }
            }
            .onChange(of: showCodeReviewPanel) { wasOpen, isOpen in
                if isOpen && !wasOpen {
                    adjustWindowForPanelToggle(isOpening: true, width: CGFloat(codeReviewPanelWidthStorage))
                } else if !isOpen && wasOpen {
                    adjustWindowForPanelToggle(isOpening: false, width: CGFloat(codeReviewPanelWidthStorage))
                    // Restore the plan panel if plan mode is still active
                    if planToggleEnabled && !showPlanPanel && !showDebugPanel {
                        showPlanPanel = true
                    }
                }
            }
            .onChange(of: effectiveContext.primaryPath) { _, newPath in
                gitPanelStore.refresh(workingDirectory: newPath)
            }
            .onChange(of: selectedConversationId) { _, _ in
                gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
                composerFrozenTimerState = nil
                composerTaskStartDate = nil
                composerTimerAutoHideTask?.cancel()
                composerTimerAutoHideTask = nil
                lastTaskEndedByManualStop = false
            }
            .onChange(of: inputText) { _, newValue in
                guard let cid = conversationId else { return }
                draftSaveTask?.cancel()
                draftSaveTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000) // 350ms debounce
                    guard !Task.isCancelled else { return }
                    draftSaveTask = nil
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        chatStore.draftTexts.removeValue(forKey: cid)
                    } else {
                        chatStore.draftTexts[cid] = newValue
                    }
                }
            }
            .onChange(of: chatStore.activeTaskConversationIds) { oldSet, newSet in
                guard let cid = conversationId else { return }
                let wasActive = oldSet.contains(cid)
                let isActive = newSet.contains(cid)
                if !wasActive && isActive {
                    composerTaskStartDate = chatStore.taskStartDate(for: cid) ?? Date()
                    composerFrozenTimerState = nil
                    composerTimerAutoHideTask?.cancel()
                    composerTimerAutoHideTask = nil
                    lastTaskEndedByManualStop = false
                }
                if wasActive && !isActive {
                    if skipNextLoadingCompletedHandling {
                        skipNextLoadingCompletedHandling = false
                        return
                    }
                    hasJustCompletedTask = true
                    gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
                    isFollowingLive = true
                    newEventsWhileDetached = 0
                    let startDate = composerTaskStartDate ?? Date()
                    let elapsed = max(0, Int(Date().timeIntervalSince(startDate)))
                    let frozen = buildComposerFrozenTimerState(
                        elapsedSeconds: elapsed,
                        endedByManualStop: lastTaskEndedByManualStop
                    )
                    composerFrozenTimerState = frozen
                    composerTaskStartDate = nil
                    composerTimerAutoHideTask?.cancel()
                    composerTimerAutoHideTask = nil
                    if let delay = frozen.autoHideDelay {
                        composerTimerAutoHideTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            guard !Task.isCancelled else { return }
                            if !self.isLoadingForCurrentConversation {
                                composerFrozenTimerState = nil
                            }
                        }
                    }
                    lastTaskEndedByManualStop = false
                }
            }

        let swarmTracked = lifecycleTracked
            .onChange(of: swarmWorkerBackend) { _, _ in syncSwarmProvider() }
            .onChange(of: claudeAllowedTools) { _, _ in
                syncClaudeProvider()
            }
            .onChange(of: unifiedToolRuntimeEnabled) { _, _ in
                syncClaudeProvider()
                syncGeminiProvider()
                scheduleToolRuntimePolicySync()
            }
            .onChange(of: mcpEditEnforcementEnabled) { _, _ in
                scheduleToolRuntimePolicySync()
            }
            .onChange(of: globalYolo) { _, _ in
                syncCodexProvider()
                syncCodeReviewRuntimeConfig()
                syncPlanProvider()
            }

        let workspaceTracked = swarmTracked
            .onChange(of: workspaceStore.activeWorkspaceId) { _, _ in
                scheduleToolRuntimePolicySync()
                syncCodeReviewRuntimeConfig()
            }
            .onChange(of: workspaceStore.workspaces.map(\.id)) { _, _ in
                scheduleToolRuntimePolicySync()
                syncCodeReviewRuntimeConfig()
            }
            .onChange(of: projectContextStore.activeContextId) { _, _ in
                scheduleToolRuntimePolicySync()
                syncCodeReviewRuntimeConfig()
            }
            .onChange(of: effectiveContext.folderPaths) { _, _ in
                scheduleToolRuntimePolicySync()
                syncCodeReviewRuntimeConfig()
            }

        return workspaceTracked
            .onChange(of: codeReviewPartitions) { _, _ in syncCodeReviewRuntimeConfig() }
            .onChange(of: codeReviewAnalysisOnly) { _, _ in syncCodeReviewRuntimeConfig() }
            .onChange(of: codeReviewMaxRounds) { _, _ in syncCodeReviewRuntimeConfig() }
            .onChange(of: codeReviewAnalysisBackend) { _, _ in syncCodeReviewRuntimeConfig() }
            .onChange(of: codeReviewExecutionBackend) { _, _ in syncCodeReviewRuntimeConfig() }
    }

}
