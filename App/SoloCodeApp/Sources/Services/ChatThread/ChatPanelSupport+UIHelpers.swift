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
    guard text.lowercased().hasPrefix("/plan") else { return false }
    guard text.count > 5 else { return true }
    let boundary = text.index(text.startIndex, offsetBy: 5)
    let next = text[boundary]
    return next.isWhitespace || next.isNewline
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
    guard hasStrictPlanCommandPrefix(text) else {
        return PlanCommandParseResult(
            displayedInput: text,
            llmPromptInput: text,
            forcePlanInline: false
        )
    }
    let remainder = String(text.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
    let prompt = remainder.isEmpty
        ? "Generate a structured plan with alternative options, pros/cons, and complexity."
        : remainder
    return PlanCommandParseResult(
        displayedInput: prompt,
        llmPromptInput: prompt,
        forcePlanInline: true
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
    let trimmed = currentInputText.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return ShiftTabPlanShortcutTransition(
            nextInputText: "/plan ",
            shouldFocusInput: true,
            shouldHighlightPlanToggle: false,
            shouldEnablePlanToggle: true
        )
    }
    if trimmed.lowercased().hasPrefix("/plan") {
        return ShiftTabPlanShortcutTransition(
            nextInputText: currentInputText,
            shouldFocusInput: true,
            shouldHighlightPlanToggle: false,
            shouldEnablePlanToggle: true
        )
    }
    return ShiftTabPlanShortcutTransition(
        nextInputText: "/plan " + trimmed,
        shouldFocusInput: true,
        shouldHighlightPlanToggle: false,
        shouldEnablePlanToggle: true
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
    // 1) off/off -> enable inline Plan (chat badge)
    if !currentPlanToggleEnabled && !currentShowPlanPanel {
        return CmdShiftPPlanShortcutTransition(
            nextPlanToggleEnabled: true,
            nextShowPlanPanel: false
        )
    }

    // 2) on/off -> open plan panel
    if currentPlanToggleEnabled && !currentShowPlanPanel {
        return CmdShiftPPlanShortcutTransition(
            nextPlanToggleEnabled: true,
            nextShowPlanPanel: true
        )
    }

    // 3) any state with panel open -> turn off everything
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

func shouldAutoOpenPlanPanel(trigger: PlanPanelAutoOpenTrigger) -> Bool {
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
    forcePlanInline || (coderMode == .agent && planToggleEnabled)
}

struct InlinePlanSummary: Equatable {
    let title: String
    let body: String
}

struct ToolTraceTurnContext: Equatable {
    let conversationId: UUID
    let assistantMessageId: UUID
    let providerId: String
}

struct PolicyAckState: Equatable {
    let expectedHash: String
    var acknowledgedHash: String?
    var violationEmitted: Bool = false

    var isSatisfied: Bool {
        acknowledgedHash == expectedHash
    }
}

struct ToolStartRequirementsState: Equatable {
    var didSeeTodoWrite: Bool = false
    var violationEmitted: Bool = false
}
