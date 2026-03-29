import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    // MARK: - Composer

    @ViewBuilder
    internal var composerArea: some View {
        let incomingComposerTodoItems = composerTodoItems
        let stabilizedComposerTodoItems = effectiveComposerTodoItems(from: incomingComposerTodoItems)
        let resolvedComposerFileChanges = composerTodoFileChanges
        let resolvedComposerMicroStatus = composerTodoMicroStatus
        let resolvedComposerStreaming = composerTodoIsStreaming
        let policyWouldShowComposerOverlay = shouldShowComposerTodoOverlay(
            items: stabilizedComposerTodoItems,
            coderMode: coderMode,
            planToggleEnabled: planToggleEnabled,
            planFlowPhase: planFlowPhase,
            planningState: planningState
        )
        let suppressDuplicatePlanMarkdown =
            shouldSuppressComposerTodoWhenDuplicatePlanMarkdownInChat(conversationId: conversationId)
        let shouldShowComposerOverlay = policyWouldShowComposerOverlay && !suppressDuplicatePlanMarkdown
        // #region agent log
        let _: Void = {
            PlanFlowDebugNDJSONLog.append(
                hypothesisId: "J",
                location: "ChatPanelView+PartH_ComposerArea.composerArea",
                message: "composer_todo_overlay_policy",
                data: [
                    "conversationId": conversationId?.uuidString.lowercased() ?? "nil",
                    "show": shouldShowComposerOverlay ? "1" : "0",
                    "policyWouldShow": policyWouldShowComposerOverlay ? "1" : "0",
                    "suppressDuplicatePlanMarkdown": suppressDuplicatePlanMarkdown ? "1" : "0",
                    "canonicalTodoCount": String(
                        conversationId.map { todoStore.canonicalTodos(for: $0).count } ?? 0
                    ),
                    "todoCount": String(stabilizedComposerTodoItems.count),
                ]
            )
        }()
        // #endregion
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
                isProjectContextAvailable: effectiveContext.hasSendableProjectContext,
                isLoading: isLoadingForCurrentConversation,
                planningState: planningState,
                runtimeRunState: executionController.runState,
                runtimeTaskStartDate: composerRuntimeStartDate,
                frozenTimerText: composerFrozenTimerText,
                frozenTimerDismissible: composerFrozenTimerDismissible,
                frozenTimerTone: composerFrozenTimerTone,
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
                    interruptTask(for: conversationId, source: "composer_stop_button")
                },
                onDismissFrozenTimer: { composerFrozenTimerState = nil },
                onVoiceAction: { handleVoiceAction() },
                onOptimizePrompt: { optimizeCurrentPrompt() },
                isOptimizingPrompt: isOptimizingPrompt,
                topOverlay: shouldShowComposerOverlay
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
                "Apri una cartella o un workspace e aggiungi almeno una cartella reale prima di inviare un messaggio."
            )
        }
    }
}
