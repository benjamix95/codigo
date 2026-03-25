import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func applyProviderSelectionModifiers<Content: View>(to content: Content) -> some View {
        content
            .onChange(of: providerRegistry.selectedProviderId) { newId in
                if shouldSyncModeOnProviderChange(
                    suppressForUserPicker: suppressModeSyncForNextProviderChange
                ) {
                    syncCoderModeToProvider(newId)
                } else {
                    suppressModeSyncForNextProviderChange = false
                }
                checkProviderAuth()
            }
            .onChangeCompat(of: selectedConversationId) { oldId, newId in
                draftSaveTask?.cancel()
                draftSaveTask = nil
                persistThreadUIState(for: oldId)
                persistDebugState(for: oldId)
                pipelineIntegrationService.unregisterDebugStore(for: oldId)
                if let oldId {
                    let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        chatStore.draftTexts.removeValue(forKey: oldId)
                    } else {
                        chatStore.draftTexts[oldId] = inputText
                    }
                    chatStore.saveDrafts()
                }
                inputText = chatStore.draftTexts[newId ?? UUID()] ?? ""
                if ignoreNextConversationChangeReset {
                    ignoreNextConversationChangeReset = false
                } else {
                    userModeOverrideUntilConversationChange = false
                }
                planHistoryStore.setSelectedEntry(id: nil)
                restoreDebugState(for: newId)
                applyPendingDebugEvents(for: newId)
                if let newId {
                    bindRuntimeDebugProjection(for: newId)
                }
                if shouldClearThreadScopedSwarmStateAfterConversationSwitch(
                    isTaskActiveForOldConversation: chatStore.isTaskActive(for: oldId)
                ) {
                    taskActivityStore.clearSwarmCards(for: oldId)
                    swarmProgressStore.clear(conversationId: oldId)
                }
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
                    inputText = chatStore.draftTexts[selectedConversationId] ?? ""
                }
                requestInitialComposerFocusIfNeeded()
            }
    }

    internal func applyRuntimeLifecycleModifiers<Content: View>(to content: Content) -> some View {
        let lifecycleTracked = content
            .onChangeCompat(of: showSwarmPanel) { wasOpen, isShowing in
                if isShowing && !wasOpen {
                    adjustWindowForPanelToggle(
                        isOpening: true,
                        width: CGFloat(uiSettings.swarmPanelWidthStorage)
                    )
                } else if !isShowing && wasOpen {
                    adjustWindowForPanelToggle(
                        isOpening: false,
                        width: CGFloat(uiSettings.swarmPanelWidthStorage)
                    )
                    if planToggleEnabled && !showPlanPanel && !showDebugPanel {
                        showPlanPanel = true
                    }
                }
            }
            .onChangeCompat(of: showDebugPanel) { wasOpen, isShowing in
                if isShowing && showPlanPanel {
                    showPlanPanel = false
                }
                if isShowing && coderMode != .debug {
                    selectMode(.debug)
                } else if !isShowing && coderMode == .debug && !debugStore.phase.isActive {
                    selectMode(.agent)
                }
                if isShowing && !wasOpen {
                    adjustWindowForPanelToggle(
                        isOpening: true,
                        width: CGFloat(uiSettings.debugPanelWidthStorage)
                    )
                } else if !isShowing && wasOpen {
                    adjustWindowForPanelToggle(
                        isOpening: false,
                        width: CGFloat(uiSettings.debugPanelWidthStorage)
                    )
                    if planToggleEnabled && !showPlanPanel {
                        showPlanPanel = true
                    }
                }
            }
            .onChange(of: debugToggleEnabled) { isEnabled in
                guard !isRestoringThreadUIState else { return }
                if isEnabled {
                    selectMode(.debug)
                } else if coderMode == .debug && !debugStore.phase.isActive {
                    selectMode(.agent)
                }
            }
            .onChangeCompat(of: showPlanPanel) { wasOpen, isOpen in
                syncPlanPanelVisibilityToRust(isOpen)
                if isOpen && showDebugPanel {
                    debugToggleEnabled = false
                    showDebugPanel = false
                }
                if isOpen && !wasOpen {
                    adjustWindowForPanelToggle(
                        isOpening: true,
                        width: CGFloat(uiSettings.planPanelWidthStorage)
                    )
                } else if !isOpen && wasOpen {
                    adjustWindowForPanelToggle(
                        isOpening: false,
                        width: CGFloat(uiSettings.planPanelWidthStorage)
                    )
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
                          ) {
                    planToggleEnabled = false
                }
            }
            .onChange(of: planToggleEnabled) { isEnabled in
                guard !isRestoringThreadUIState else { return }
                if !isEnabled, showPlanPanel, shouldAllowPlanToggleDeactivation(phase: planFlowPhase) {
                    showPlanPanel = false
                    planningState = .idle
                    planFlowPhase = .idle
                    clearPlanStreamingState()
                    planHistoryStore.setSelectedEntry(id: nil)
                }
            }
            .onChangeCompat(of: showCodeReviewPanel) { wasOpen, isOpen in
                if isOpen && !wasOpen {
                    adjustWindowForPanelToggle(
                        isOpening: true,
                        width: CGFloat(uiSettings.codeReviewPanelWidthStorage)
                    )
                } else if !isOpen && wasOpen {
                    adjustWindowForPanelToggle(
                        isOpening: false,
                        width: CGFloat(uiSettings.codeReviewPanelWidthStorage)
                    )
                    if planToggleEnabled && !showPlanPanel && !showDebugPanel {
                        showPlanPanel = true
                    }
                }
            }
            .onChange(of: effectiveContext.primaryPath) { newPath in
                gitPanelStore.refresh(workingDirectory: newPath)
            }
            .onChange(of: selectedConversationId) { _ in
                gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
                DispatchQueue.main.async {
                    composerFrozenTimerState = nil
                    composerTaskStartDate = nil
                    composerTimerAutoHideTask?.cancel()
                    composerTimerAutoHideTask = nil
                    lastTaskEndedByManualStop = false
                }
            }
            .onChange(of: inputText) { newValue in
                guard let cid = conversationId else { return }
                // Skip draft persistence while voice dictation is writing live partial text.
                guard voicePrefixText == nil else { return }
                draftSaveTask?.cancel()
                draftSaveTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled else { return }
                    draftSaveTask = nil
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        chatStore.draftTexts.removeValue(forKey: cid)
                    } else {
                        chatStore.draftTexts[cid] = newValue
                    }
                    chatStore.saveDrafts()
                }
            }
            .onChange(of: voiceInputController.transcript) { newTranscript in
                guard let prefix = voicePrefixText else { return }
                let sep = prefix.isEmpty ? "" : (prefix.hasSuffix(" ") ? "" : " ")
                let partial = newTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                inputText = partial.isEmpty ? prefix : prefix + sep + partial
            }
            .onChangeCompat(of: chatStore.activeTaskConversationIds) { oldSet, newSet in
                guard let cid = conversationId else { return }
                let wasActive = oldSet.contains(cid)
                let isActive = newSet.contains(cid)
                if !wasActive && isActive {
                    DispatchQueue.main.async {
                        composerTaskStartDate = chatStore.taskStartDate(for: cid) ?? Date()
                        composerFrozenTimerState = nil
                        composerTimerAutoHideTask?.cancel()
                        composerTimerAutoHideTask = nil
                        lastTaskEndedByManualStop = false
                    }
                }
                if wasActive && !isActive {
                    if skipNextLoadingCompletedHandling {
                        skipNextLoadingCompletedHandling = false
                        return
                    }
                    DispatchQueue.main.async {
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
            }
        let swarmTracked = lifecycleTracked
            .onChange(of: swarmReviewSettings.swarmWorkerBackend) { _ in syncSwarmProvider() }
            .onChange(of: providerSettings.claudeAllowedTools) { _ in syncClaudeProvider() }
            .onChange(of: uiSettings.unifiedToolRuntimeEnabled) { _ in
                syncClaudeProvider()
                syncGeminiProvider()
                scheduleToolRuntimePolicySync()
            }
            .onChange(of: uiSettings.mcpEditEnforcementEnabled) { _ in
                scheduleToolRuntimePolicySync()
            }
            .onChange(of: uiSettings.globalYolo) { _ in
                syncCodexProvider()
                syncCodeReviewRuntimeConfig()
                syncPlanProvider()
            }
        let workspaceTracked = swarmTracked
            .onChange(of: workspaceStore.activeWorkspaceId) { _ in
                scheduleToolRuntimePolicySync()
                syncCodeReviewRuntimeConfig()
            }
            .onChange(of: workspaceStore.workspaces.map(\.id)) { _ in
                scheduleToolRuntimePolicySync()
                syncCodeReviewRuntimeConfig()
            }
            .onChange(of: projectContextStore.activeContextId) { _ in
                scheduleToolRuntimePolicySync()
                syncCodeReviewRuntimeConfig()
            }
            .onChange(of: effectiveContext.folderPaths) { _ in
                scheduleToolRuntimePolicySync()
                syncCodeReviewRuntimeConfig()
            }
        return workspaceTracked
            .onChange(of: swarmReviewSettings.codeReviewPartitions) { _ in syncCodeReviewRuntimeConfig() }
            .onChange(of: swarmReviewSettings.codeReviewAnalysisOnly) { _ in syncCodeReviewRuntimeConfig() }
            .onChange(of: swarmReviewSettings.codeReviewMaxRounds) { _ in syncCodeReviewRuntimeConfig() }
            .onChange(of: swarmReviewSettings.codeReviewAnalysisBackend) { _ in syncCodeReviewRuntimeConfig() }
            .onChange(of: swarmReviewSettings.codeReviewExecutionBackend) { _ in syncCodeReviewRuntimeConfig() }
    }
}
