import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    static let attachmentPastedNotification = Notification.Name("CoderIDE.AttachmentPasted")
    static let planBuildShortcutNotification = Notification.Name("CoderIDE.PlanBuildShortcutPressed")
    static let debugPanelToggleNotification = Notification.Name("CoderIDE.DebugPanelToggle")
    static let threadDeletionRequestedNotification = Notification.Name("CoderIDE.ThreadDeletionRequested")
    static let threadSearchAskAINotification = Notification.Name("CoderIDE.ThreadSearchAskAI")
    static let markdownExportContentType = UTType(filenameExtension: "md") ?? .plainText

    var topInteractiveInset: CGFloat { 7 }
    var chatColumnMaxWidth: CGFloat { 720 }
    var chatScrollTopAnchorId: String { "chat-scroll-top-anchor" }
    var chatScrollBottomAnchorId: String { "chat-scroll-bottom-anchor" }
    var activeModeColor: Color { modeColor(for: coderMode) }
    var activeModeGradient: LinearGradient { modeGradient(for: coderMode) }

    var showPlanRequestIndicator: Bool {
        planToggleEnabled
    }

    var composerRuntimeStartDate: Date? {
        guard isLoadingForCurrentConversation else { return nil }
        return snapshotPipelineConversationSnapshot?.jobStartTime
            ?? chatStore.taskStartDate(for: conversationId)
            ?? composerTaskStartDate
    }

    var composerFrozenTimerText: String? { composerFrozenTimerState?.text }
    var composerFrozenTimerDismissible: Bool { composerFrozenTimerState?.dismissible == true }
    var composerFrozenTimerTone: ComposerFrozenTimerState.Tone {
        composerFrozenTimerState?.tone ?? .neutral
    }

    var shouldShowTaskPanelTodoSection: Bool {
        let planFlowActive =
            coderMode == .plan
            || planToggleEnabled
            || planFlowPhase == .analyzing
            || planFlowPhase == .questioning
            || planFlowPhase == .generating
            || planFlowPhase == .proposalReady
            || planFlowPhase == .readyToBuild
            || planFlowPhase == .building
        return !planFlowActive
    }

    var isPlanPreChoiceState: Bool {
        if planningState != .idle {
            return true
        }
        switch planFlowPhase {
        case .analyzing, .questioning, .generating, .proposalReady:
            return true
        case .idle, .readyToBuild, .building:
            return false
        }
    }

    var hasInlinePlanSession: Bool {
        coderMode == .plan || (coderMode == .agent && planToggleEnabled)
    }

    var hasActivePlanContext: Bool {
        hasActivePlanContext(for: conversationId)
    }

    var planPanelConversationId: UUID? { conversationId }

    var body: some View {
        applyNotificationAndImporterModifiers(
            to: applyRuntimeLifecycleModifiers(
                to: applyProviderSelectionModifiers(to: rootLayout)
            )
        )
    }
}
