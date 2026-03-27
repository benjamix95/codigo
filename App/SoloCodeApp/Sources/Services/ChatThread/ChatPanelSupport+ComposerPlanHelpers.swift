import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

struct ComposerFrozenTimerState: Equatable {
    let text: String
    let dismissible: Bool
    let autoHideDelay: TimeInterval?
}

func formatComposerElapsed(_ seconds: Int) -> String {
    let safeSeconds = max(0, seconds)
    let minutes = safeSeconds / 60
    let remainder = safeSeconds % 60
    return String(format: "%d:%02d", minutes, remainder)
}

func buildComposerFrozenTimerState(
    elapsedSeconds: Int,
    endedByManualStop: Bool
) -> ComposerFrozenTimerState {
    ComposerFrozenTimerState(
        text: formatComposerElapsed(elapsedSeconds),
        dismissible: !endedByManualStop,
        autoHideDelay: endedByManualStop ? 2.0 : nil
    )
}

struct PlanCommandParseResult: Equatable {
    let displayedInput: String
    let llmPromptInput: String
    let forcePlanInline: Bool
}

func hasStrictPlanCommandPrefix(_ text: String) -> Bool {
    _ = text
    return false
}

func shouldUseClarificationPrompt(
    coderMode: CoderMode,
    planningState: PlanningState,
    shouldRunPlanInline: Bool
) -> Bool {
    guard case .awaitingClarification = planningState else { return false }
    return coderMode == .plan || shouldRunPlanInline
}

func parsePlanCommandInput(_ rawInput: String) -> PlanCommandParseResult {
    let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    return PlanCommandParseResult(
        displayedInput: text,
        llmPromptInput: text,
        forcePlanInline: false
    )
}

func composerContextFolderPath(for effectiveContext: EffectiveContext) -> String? {
    guard let context = effectiveContext.context, context.folderPaths.count > 1 else { return nil }
    return context.activeFolderPath
}

@MainActor
func resolveComposerSendConversationId(
    selectedConversationId: UUID?,
    effectiveContext: EffectiveContext,
    coderMode: CoderMode,
    chatStore: ChatStore
) -> UUID {
    if let selectedConversationId {
        return selectedConversationId
    }

    let contextFolderPath = composerContextFolderPath(for: effectiveContext)
    if let reusable = chatStore.reusableEmptyConversation(
        contextId: effectiveContext.contextId,
        contextFolderPath: contextFolderPath,
        mode: coderMode
    ) {
        return reusable.id
    }

    return chatStore.createConversation(
        contextId: effectiveContext.contextId,
        contextFolderPath: contextFolderPath,
        mode: coderMode
    )
}

func isShiftTabShortcut(flags: NSEvent.ModifierFlags, charsIgnoringModifiers: String?, keyCode: UInt16)
    -> Bool
{
    let normalized = flags.intersection(.deviceIndependentFlagsMask)
    let isBacktabChar = charsIgnoringModifiers == "\u{19}"
    let isTabKeycode = keyCode == 48
    return (isBacktabChar || isTabKeycode)
        && normalized.contains(.shift)
        && !normalized.contains(.command)
        && !normalized.contains(.option)
        && !normalized.contains(.control)
}

func isCmdShiftPShortcut(flags: NSEvent.ModifierFlags, charsIgnoringModifiers: String?) -> Bool {
    let normalized = flags.intersection(.deviceIndependentFlagsMask)
    return normalized.contains(.command)
        && normalized.contains(.shift)
        && !normalized.contains(.option)
        && !normalized.contains(.control)
        && charsIgnoringModifiers?.lowercased() == "p"
}

struct ShiftTabPlanShortcutTransition: Equatable {
    let nextInputText: String
    let shouldFocusInput: Bool
    let shouldHighlightPlanToggle: Bool
    let shouldEnablePlanToggle: Bool
}

func evaluateShiftTabPlanShortcut(currentInputText: String) -> ShiftTabPlanShortcutTransition {
    return ShiftTabPlanShortcutTransition(
        nextInputText: currentInputText,
        shouldFocusInput: true,
        shouldHighlightPlanToggle: false,
        shouldEnablePlanToggle: false
    )
}

func shouldOpenPlanPanelAfterShiftTab(
    shouldEnablePlanToggle: Bool,
    currentShowPlanPanel: Bool
) -> Bool {
    shouldEnablePlanToggle && !currentShowPlanPanel
}

struct CmdShiftPPlanShortcutTransition: Equatable {
    let nextPlanToggleEnabled: Bool
    let nextShowPlanPanel: Bool
}

func evaluateCmdShiftPPlanShortcut(
    currentPlanToggleEnabled: Bool,
    currentShowPlanPanel: Bool
) -> CmdShiftPPlanShortcutTransition {
    if !currentPlanToggleEnabled && !currentShowPlanPanel {
        return CmdShiftPPlanShortcutTransition(
            nextPlanToggleEnabled: true,
            nextShowPlanPanel: false
        )
    }

    if currentPlanToggleEnabled && !currentShowPlanPanel {
        return CmdShiftPPlanShortcutTransition(
            nextPlanToggleEnabled: true,
            nextShowPlanPanel: true
        )
    }

    return CmdShiftPPlanShortcutTransition(
        nextPlanToggleEnabled: false,
        nextShowPlanPanel: false
    )
}

enum PlanPanelAutoOpenTrigger: Equatable {
    case flowStarted
    case planStepUpdate
    case awaitingClarification
    case awaitingChoice
    case proposalReady
}

func shouldAutoOpenPlanPanel(
    trigger: PlanPanelAutoOpenTrigger,
    planToggleEnabled: Bool
) -> Bool {
    guard shouldHonorPlanUserOptIn(planToggleEnabled: planToggleEnabled) else {
        return false
    }
    switch trigger {
    case .flowStarted:
        return false
    case .awaitingClarification:
        return true
    case .awaitingChoice:
        return true
    case .proposalReady:
        return true
    case .planStepUpdate:
        return false
    }
}

func resolveShouldRunPlanInline(
    forcePlanInline: Bool,
    coderMode: CoderMode,
    planToggleEnabled: Bool
) -> Bool {
    _ = forcePlanInline
    return coderMode == .agent && planToggleEnabled
}
