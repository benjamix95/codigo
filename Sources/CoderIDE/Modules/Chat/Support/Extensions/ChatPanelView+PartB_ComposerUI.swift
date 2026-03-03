import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @ViewBuilder
    internal var planPanelSidebar: some View {
        PlanPanelView(
            todoStore: todoStore,
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            conversationId: planPanelConversationId,
            isCurrentConversationLoading: isLoadingForCurrentConversation,
            planningState: planningState,
            planFlowPhase: planFlowPhase,
            planStreamingContent: planStreamingContent,
            showHistorySection: shouldShowPlanPanelHistory(source: planPanelPresentationSource),
            workspaceSource: planPanelPresentationSource,
            onClose: {
                showPlanPanel = false
            },
            onSelectOption: { option, providerId in
                selectPlanChoice(
                    option.fullText,
                    fromPlanConversationId: planPanelConversationId,
                    providerOverrideId: providerId
                )
            },
            onCustomResponse: { response in
                handleCustomPlanResponseSelection(
                    response,
                    fromPlanConversationId: planPanelConversationId
                )
            },
            onSubmitClarificationAnswers: { answers in
                submitPlanClarificationAnswers(answers)
            },
            onBuild: { choice, providerId, allowIdleRebuild in
                executeWithPlanChoice(
                    choice,
                    fromPlanConversationId: planPanelConversationId,
                    providerOverrideId: providerId,
                    allowIdleRebuild: allowIdleRebuild
                )
            },
            onStop: {
                lastTaskEndedByManualStop = true
                interruptTask()
            },
            onHistoryEntrySelectedForBuild: {
                if planFlowPhase == .idle, planningState == .idle {
                    planFlowPhase = .readyToBuild
                }
            }
        )
        .frame(width: CGFloat(planPanelWidthStorage))
    }

    @ViewBuilder
    internal var debugPanelSidebar: some View {
        DebugPanelView(
            debugStore: debugStore,
            taskActivities: scopedTaskActivities(for: conversationId),
            todoStore: todoStore,
            onClose: {
                debugToggleEnabled = false
                showDebugPanel = false
                if coderMode == .debug && !debugStore.phase.isActive {
                    selectMode(.agent)
                }
            },
            onSubmitQuestion: { question in
                let debugPrompt = "[DEBUG] \(question)"
                inputText = debugPrompt
                sendMessage()
            },
            onStop: {
                lastTaskEndedByManualStop = true
                interruptTask()
                debugStore.resetSession()
            },
            onProceed: {
                debugStore.confirmReproduced()
                // Tell the agent to proceed with investigation
                inputText = "[DEBUG] Bug reproduced. Proceed with investigation."
                sendMessage()
            },
            onFixed: {
                let filesToClean = debugStore.beginMarkFixed(summary: debugStore.resolutionSummary)
                if filesToClean.isEmpty {
                    inputText = "[DEBUG] Run debug_clean now and confirm cleanup succeeded, then resolve the session."
                } else {
                    let fileList = filesToClean.joined(separator: ", ")
                    inputText = "[DEBUG] Run debug_clean for these files: \(fileList). After success, resolve the session."
                }
                sendMessage()
            }
        )
        .frame(width: CGFloat(debugPanelWidthStorage))
    }

    @ViewBuilder
    internal var swarmPanelSidebar: some View {
        SwarmPanelView(
            taskActivityStore: taskActivityStore,
            swarmProgressStore: swarmProgressStore,
            todoStore: todoStore,
            chatStore: chatStore,
            conversationId: conversationId,
            isTaskRunning: isLoadingForCurrentConversation,
            selectedSwarmId: $selectedSwarmId,
            swarmOrchestrator: $swarmOrchestrator,
            swarmWorkerBackend: $swarmWorkerBackend,
            onClose: {
                showSwarmPanel = false
            },
            onOpenFile: { openFilesStore.openFile($0) },
            onSyncSwarmProvider: syncSwarmProvider
        )
        .frame(width: CGFloat(swarmPanelWidthStorage))
    }

    internal var codeReviewPanelSidebar: some View {
        CodeReviewPanelView(
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            swarmProgressStore: swarmProgressStore,
            todoStore: todoStore,
            conversationId: conversationId,
            isTaskRunning: isLoadingForCurrentConversation,
            coderMode: coderMode,
            codeReviewPartitions: $codeReviewPartitions,
            codeReviewAnalysisOnly: $codeReviewAnalysisOnly,
            codeReviewMaxRounds: $codeReviewMaxRounds,
            codeReviewAnalysisBackend: $codeReviewAnalysisBackend,
            codeReviewExecutionBackend: $codeReviewExecutionBackend,
            onClose: {
                showCodeReviewPanel = false
            },
            onOpenFile: { openFilesStore.openFile($0) },
            onRunSlashCommand: { command in
                inputText = command
                isInputFocused = true
                sendMessage()
            },
            onSelectMode: { mode in
                selectMode(mode)
            }
        )
        .frame(width: CGFloat(codeReviewPanelWidthStorage))
    }

    @ViewBuilder
    internal var swarmDashboardArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SwarmProgressView(
                    store: swarmProgressStore,
                    activities: taskActivityStore.activities,
                    isTaskRunning: isLoadingForCurrentConversation,
                    onSelectSwarm: { swarmId in
                        showSwarmPanel = true
                        selectedSwarmId = swarmId
                    }
                )
                if taskPanelEnabled {
                    if !taskActivityStore.concreteRecentActivities(limit: 1).isEmpty || !todoStore.todos.isEmpty {
                        TaskActivityPanel(
                            chatStore: chatStore,
                            taskActivityStore: taskActivityStore,
                            todoStore: todoStore,
                            conversationId: conversationId,
                            coderMode: coderMode,
                            debugPhase: debugStore.phase,
                            onOpenFile: { openFilesStore.openFile($0) },
                            effectivePrimaryPath: effectiveContext.primaryPath,
                            showTodoSection: shouldShowTaskPanelTodoSection
                        )
                    } else {
                        Text("No swarm activity available.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                } else {
                    Text("Swarm activity panel hidden.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: chatColumnMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    internal func appendComposerAttachments(_ incoming: [ComposerAttachment]) {
        guard !incoming.isEmpty else { return }
        var current = attachedComposerAttachments
        var seenPaths = Set(current.map { $0.url.standardizedFileURL.path })

        for item in incoming {
            guard current.count < AttachmentIntakeService.maxAttachmentsPerMessage else { break }
            if let size = item.sizeBytes, size > AttachmentIntakeService.maxAttachmentSizeBytes {
                continue
            }
            let path = item.url.standardizedFileURL.path
            if seenPaths.insert(path).inserted {
                current.append(item)
            }
        }
        attachedComposerAttachments = current
    }

    internal func handleAttachmentSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let hasHeic = urls.contains { ImageAttachmentHelper.isHeic(url: $0) }
            if hasHeic { isConvertingHeic = true }
            let imported = AttachmentIntakeService.importURLs(
                urls,
                existingCount: attachedComposerAttachments.count
            )
            appendComposerAttachments(imported.accepted)
            if hasHeic { isConvertingHeic = false }
        case .failure:
            break
        }
    }

    internal func installPasteMonitor() {
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if shouldHandlePlanKeyboardShortcut(isInputFocused: isInputFocused) && isCmdShiftP(event) {
                cyclePlanShortcutState()
                return nil
            }
            if shouldHandlePlanKeyboardShortcut(isInputFocused: isInputFocused) && isShiftTab(event) {
                handleShiftTabPlanShortcut()
                return nil
            }
            if showPlanPanel
                && event.modifierFlags.contains(.command)
                && !event.modifierFlags.contains(.shift)
                && !event.modifierFlags.contains(.option)
                && !event.modifierFlags.contains(.control)
                && event.keyCode == 36 {
                NotificationCenter.default.post(name: Self.planBuildShortcutNotification, object: nil)
                return nil
            }
            // Cmd+Shift+D toggles debug panel
            let normalized = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if normalized.contains([.command, .shift]),
               !normalized.contains(.option),
               !normalized.contains(.control),
               event.charactersIgnoringModifiers?.lowercased() == "d" {
                debugToggleEnabled.toggle()
                return nil
            }
            guard event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v"
            else {
                return event
            }
            let attachments = AttachmentIntakeService.attachmentsFromPasteboard()
            if !attachments.isEmpty {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Self.attachmentPastedNotification,
                        object: nil,
                        userInfo: ["attachments": attachments]
                    )
                }
                return nil
            }
            return event
        }
    }

    internal func isShiftTab(_ event: NSEvent) -> Bool {
        isShiftTabShortcut(
            flags: event.modifierFlags,
            charsIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode
        )
    }

    internal func isCmdShiftP(_ event: NSEvent) -> Bool {
        isCmdShiftPShortcut(
            flags: event.modifierFlags,
            charsIgnoringModifiers: event.charactersIgnoringModifiers
        )
    }

    internal func removePasteMonitor() {
        if let m = pasteMonitor {
            NSEvent.removeMonitor(m)
            pasteMonitor = nil
        }
    }

    internal func restorePlanStateIfNeeded(for conversationId: UUID?) {
        clearPlanStreamingState()
        let hasActiveTask = conversationId.map { activeBuildPlanConversationId == $0 || chatStore.isTaskActive(for: $0) } ?? false
        if !hasActiveTask {
            planClarificationCycles = 0
            planShouldRunInline = false
        }
        guard let conversationId else {
            planAnalysisContext = ""
            planUserRequest = ""
            planClarificationAnswers = ""
            planningState = .idle
            planFlowPhase = .idle
            return
        }
        // If a plan build is actively running for this conversation, restore .building.
        // Don't clear plan context — the background task still needs it.
        if activeBuildPlanConversationId == conversationId {
            planFlowPhase = .building
            planningState = .idle
            return
        }
        // If a non-build task is active (e.g., plan generation phases 1–3),
        // preserve the current planFlowPhase — the running task manages it.
        if chatStore.isTaskActive(for: conversationId) {
            return
        }
        // No active flow — safe to reset per-flow context
        planAnalysisContext = ""
        planUserRequest = ""
        planClarificationAnswers = ""
        guard let board = chatStore.planBoard(for: conversationId) else {
            planningState = .idle
            planFlowPhase = .idle
            return
        }
        let chosenPath = board.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasValidChosenPath =
            !chosenPath.isEmpty &&
            PlanOptionsParser.hasRequiredTodoHeader(chosenPath) &&
            !PlanOptionsParser.extractTodosFromOptionText(chosenPath).isEmpty
        if hasValidChosenPath {
            planFlowPhase = .readyToBuild
            planningState = .idle
            return
        }
        let compliantOptions = PlanOptionsParser.todoCompliantOptions(from: board.options)
        if !compliantOptions.isEmpty {
            let proposalContent: String
            if !chosenPath.isEmpty {
                proposalContent = chosenPath
            } else if let first = compliantOptions.min(by: { $0.id < $1.id })?.fullText,
                      !first.isEmpty {
                proposalContent = first
            } else {
                proposalContent = board.goal
            }
            planFlowPhase = .proposalReady
            planningState = .awaitingChoice(planContent: proposalContent, options: compliantOptions)
            return
        }
        planningState = .idle
        planFlowPhase = .idle
    }

    internal func openPlanPanelForCurrentContext(
        preserveHistorySelection: Bool = false,
        source: PlanPanelPresentationSource = .manualDeepLink
    ) {
        planPanelPresentationSource = source
        if source == .automaticFlow || !preserveHistorySelection {
            planHistoryStore.setSelectedEntry(id: nil)
        }
        showPlanPanel = true
    }

    internal func cyclePlanShortcutState() {
        guard !isPlanShortcutCycling else { return }
        isPlanShortcutCycling = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                isPlanShortcutCycling = false
            }
        }

        let transition = evaluateCmdShiftPPlanShortcut(
            currentPlanToggleEnabled: planToggleEnabled,
            currentShowPlanPanel: showPlanPanel
        )
        let requestedPlanToggleOff = !transition.nextPlanToggleEnabled
        let canDeactivatePlanToggle = shouldAllowPlanToggleDeactivation(phase: planFlowPhase)
        let resolvedPlanToggleEnabled =
            requestedPlanToggleOff && !canDeactivatePlanToggle
            ? true
            : transition.nextPlanToggleEnabled
        withAnimation(.easeInOut(duration: 0.2)) {
            planToggleEnabled = resolvedPlanToggleEnabled
                if transition.nextShowPlanPanel {
                    openPlanPanelForCurrentContext(source: .manualShortcut)
                } else {
                    showPlanPanel = false
                    if requestedPlanToggleOff && canDeactivatePlanToggle {
                        planningState = .idle
                        planFlowPhase = .idle
                        clearPlanStreamingState()
                        planHistoryStore.setSelectedEntry(id: nil)
                    }
                }
            }
            isInputFocused = true
        }

    internal func handleShiftTabPlanShortcut() {
        let transition = evaluateShiftTabPlanShortcut(currentInputText: inputText)

        inputText = transition.nextInputText
        if transition.shouldEnablePlanToggle {
            planToggleEnabled = true
            if shouldOpenPlanPanelAfterShiftTab(
                shouldEnablePlanToggle: transition.shouldEnablePlanToggle,
                currentShowPlanPanel: showPlanPanel
            ) {
                openPlanPanelForCurrentContext(source: .manualShortcut)
            }
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPlanTabHovered = transition.shouldHighlightPlanToggle
        }

        if transition.shouldHighlightPlanToggle {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                isPlanTabHovered = false
            }
        }

        if transition.shouldFocusInput {
            isInputFocused = true
        }
    }

    internal func downloadPlanEntry(_ entry: PlanHistoryEntry) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        let baseName = entry.title.isEmpty ? "PLAN" : entry.title
        savePanel.nameFieldStringValue = "\(baseName.replacingOccurrences(of: " ", with: "_")).md"
        let content = entry.markdown
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    internal func copyWholeChatToClipboard() {
        guard let markdown = chatStore.exportConversationMarkdown(conversationId: conversationId) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        didCopyAllChat = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [self] in
            didCopyAllChat = false
        }
    }

}
