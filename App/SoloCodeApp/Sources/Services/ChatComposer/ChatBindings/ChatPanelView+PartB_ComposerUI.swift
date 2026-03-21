import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
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
        guard pasteMonitor == nil else { return }
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
        flushPlanStreamingContent()
        if let conversationId {
            planStreamingContent = planStreamingContentByConversation[conversationId] ?? ""
        } else {
            planStreamingContent = ""
        }
        let hasActivePlanBuild = isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
        if !hasActivePlanBuild {
            planClarificationCycles = 0
            planShouldRunInline = false
        }
        guard let conversationId else {
            planAnalysisContext = ""
            planUserRequest = ""
            planClarificationAnswers = ""
            planClarificationQuestionnaire = nil
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
        let isBuildScopedConversation = isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
        // Preserve state only when this conversation is the active plan-build scope.
        // Generic active tasks (non-plan) must not pin plan UI state across threads.
        if isBuildScopedConversation {
            return
        }
        if let projection = projectPlanningSnapshot(conversationId: conversationId) {
            applyPlanStateMirror(
                planSnapshot: projection.snapshot.plan,
                runtimeSnapshot: projection.state.runtimeSnapshot,
                conversationId: conversationId
            )
            return
        }
        if let questionsMarkdown = clarificationQuestionsMarkdownForRestore(
            planStreamingContentByConversation[conversationId] ?? "",
            isBuildScopedConversation: isBuildScopedConversation
        ) {
            planClarificationQuestionnaire = PlanOptionsParser.parseClarificationQuestionnaire(from: questionsMarkdown)
            planFlowPhase = .questioning
            planningState = .awaitingClarification(questions: questionsMarkdown)
            planStreamingContent = questionsMarkdown
            return
        }
        // Rust projection unavailable: reset to safe idle fallback.
        planAnalysisContext = ""
        planUserRequest = ""
        planClarificationAnswers = ""
        planClarificationQuestionnaire = nil
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
        syncPlanPanelVisibilityToRust(true)
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
