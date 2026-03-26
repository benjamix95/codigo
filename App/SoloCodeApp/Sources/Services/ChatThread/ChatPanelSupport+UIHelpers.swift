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

struct ChatPanelComposerViewState {
    var inputText = ""
    var isInputFocused = false
    var didAutoFocusComposerOnLaunch = false
    var composerAutoFocusTask: Task<Void, Never>?
    var draftSaveTask: Task<Void, Never>?
    var attachedComposerAttachments: [ComposerAttachment] = []
    var composerCodeReviewModes: Set<CodeReviewPanelMode> = [.standard, .bugFinder, .securityAudit]
    var isSelectingImage = false
    var isComposerDropTargeted = false
    var isConvertingHeic = false
    var pasteMonitor: Any?
    var composerFrozenTimerState: ComposerFrozenTimerState?
    var composerTimerAutoHideTask: Task<Void, Never>?
    var composerTaskStartDate: Date?
    var lastTaskEndedByManualStop = false
    var isOptimizingPrompt = false
    var showPromptOptimizerPopup = false
    var optimizedPromptResult = ""
    var promptOptimizerTask: Task<Void, Never>?
    /// Text that was in the composer before voice dictation started; used to restore on cancel.
    var voicePrefixText: String?
}

struct ChatPanelPlanViewState {
    var planningState: PlanningState = .idle
    var planFlowPhase: PlanFlowPhase = .idle
    var planAnalysisContext = ""
    var planUserRequest = ""
    var planClarificationAnswers = ""
    var planClarificationQuestionnaire: PlanClarificationQuestionnaire?
    var planClarificationCycles = 0
    var planStreamingContent = ""
    var planStreamingContentByConversation: [UUID: String] = [:]
    var planQuestionToolRequestEpoch = 0
    var planShouldRunInline = false
    var activeBuildPlanConversationId: UUID?
    var activeBuildAgentConversationId: UUID?
    var suppressedEmptyBuildAssistantMessageIds: Set<UUID> = []
    var isPlanSummaryCollapsed = false
    var isPlanTabHovered = false
    var isPlanShortcutCycling = false
    var inlinePlanSummaries: [UUID: InlinePlanSummary] = [:]
}

struct ChatPanelThreadViewState {
    var planToggleEnabled = false
    var debugToggleEnabled = false
    var selectedSwarmId: String?
    var planPanelPresentationSource: PlanPanelPresentationSource = .manualDeepLink
    var threadUIStateByConversation: [UUID: ChatThreadUIState] = [:]
    var isRestoringThreadUIState = false
    var hasJustCompletedTask = false
    var showRateLimitAlert = false
    var rateLimitAlertText = ""
    var didCopyAllChat = false
    var isFollowingLive = true
    var newEventsWhileDetached = 0
    var chatHeaderWidth: CGFloat = 800
}

struct ChatPanelInteractionViewState {
    var isProviderReady = false
    var isSummarizing = false
    var isRewinding = false
    /// Evita doppi avvii plan build mentre il checkpoint Git gira fuori dal main thread.
    var isPlanBuildCheckpointInFlight = false
    var isAnyAgentProviderReady = false
    var checkProviderAuthGeneration = 0
    var userModeOverrideUntilConversationChange = false
    var suppressModeSyncForNextProviderChange = false
    var ignoreNextConversationChangeReset = false
    var skipNextLoadingCompletedHandling = false
}

extension ChatPanelView {
    var inputText: String {
        get { composerState.inputText }
        nonmutating set { composerState.inputText = newValue }
    }

    var isInputFocused: Bool {
        get { composerState.isInputFocused }
        nonmutating set { composerState.isInputFocused = newValue }
    }

    var didAutoFocusComposerOnLaunch: Bool {
        get { composerState.didAutoFocusComposerOnLaunch }
        nonmutating set { composerState.didAutoFocusComposerOnLaunch = newValue }
    }

    var composerAutoFocusTask: Task<Void, Never>? {
        get { composerState.composerAutoFocusTask }
        nonmutating set { composerState.composerAutoFocusTask = newValue }
    }

    var draftSaveTask: Task<Void, Never>? {
        get { composerState.draftSaveTask }
        nonmutating set { composerState.draftSaveTask = newValue }
    }

    var attachedComposerAttachments: [ComposerAttachment] {
        get { composerState.attachedComposerAttachments }
        nonmutating set { composerState.attachedComposerAttachments = newValue }
        nonmutating _modify { yield &composerState.attachedComposerAttachments }
    }

    var composerCodeReviewModes: Set<CodeReviewPanelMode> {
        get { composerState.composerCodeReviewModes }
        nonmutating set { composerState.composerCodeReviewModes = newValue }
        nonmutating _modify { yield &composerState.composerCodeReviewModes }
    }

    var isSelectingImage: Bool {
        get { composerState.isSelectingImage }
        nonmutating set { composerState.isSelectingImage = newValue }
    }

    var isComposerDropTargeted: Bool {
        get { composerState.isComposerDropTargeted }
        nonmutating set { composerState.isComposerDropTargeted = newValue }
    }

    var isConvertingHeic: Bool {
        get { composerState.isConvertingHeic }
        nonmutating set { composerState.isConvertingHeic = newValue }
    }

    var pasteMonitor: Any? {
        get { composerState.pasteMonitor }
        nonmutating set { composerState.pasteMonitor = newValue }
    }

    var composerFrozenTimerState: ComposerFrozenTimerState? {
        get { composerState.composerFrozenTimerState }
        nonmutating set { composerState.composerFrozenTimerState = newValue }
    }

    var composerTimerAutoHideTask: Task<Void, Never>? {
        get { composerState.composerTimerAutoHideTask }
        nonmutating set { composerState.composerTimerAutoHideTask = newValue }
    }

    var composerTaskStartDate: Date? {
        get { composerState.composerTaskStartDate }
        nonmutating set { composerState.composerTaskStartDate = newValue }
    }

    var lastTaskEndedByManualStop: Bool {
        get { composerState.lastTaskEndedByManualStop }
        nonmutating set { composerState.lastTaskEndedByManualStop = newValue }
    }

    var isOptimizingPrompt: Bool {
        get { composerState.isOptimizingPrompt }
        nonmutating set { composerState.isOptimizingPrompt = newValue }
    }

    var showPromptOptimizerPopup: Bool {
        get { composerState.showPromptOptimizerPopup }
        nonmutating set { composerState.showPromptOptimizerPopup = newValue }
    }

    var optimizedPromptResult: String {
        get { composerState.optimizedPromptResult }
        nonmutating set { composerState.optimizedPromptResult = newValue }
    }

    var promptOptimizerTask: Task<Void, Never>? {
        get { composerState.promptOptimizerTask }
        nonmutating set { composerState.promptOptimizerTask = newValue }
    }

    var voicePrefixText: String? {
        get { composerState.voicePrefixText }
        nonmutating set { composerState.voicePrefixText = newValue }
    }

    var planningState: PlanningState {
        get { planState.planningState }
        nonmutating set { planState.planningState = newValue }
    }

    var planFlowPhase: PlanFlowPhase {
        get { planState.planFlowPhase }
        nonmutating set { planState.planFlowPhase = newValue }
    }

    var planAnalysisContext: String {
        get { planState.planAnalysisContext }
        nonmutating set { planState.planAnalysisContext = newValue }
    }

    var planUserRequest: String {
        get { planState.planUserRequest }
        nonmutating set { planState.planUserRequest = newValue }
    }

    var planClarificationAnswers: String {
        get { planState.planClarificationAnswers }
        nonmutating set { planState.planClarificationAnswers = newValue }
    }

    var planClarificationQuestionnaire: PlanClarificationQuestionnaire? {
        get { planState.planClarificationQuestionnaire }
        nonmutating set { planState.planClarificationQuestionnaire = newValue }
    }

    var planClarificationCycles: Int {
        get { planState.planClarificationCycles }
        nonmutating set { planState.planClarificationCycles = newValue }
    }

    var planStreamingContent: String {
        get { planState.planStreamingContent }
        nonmutating set { planState.planStreamingContent = newValue }
    }

    var planStreamingContentByConversation: [UUID: String] {
        get { planState.planStreamingContentByConversation }
        nonmutating set { planState.planStreamingContentByConversation = newValue }
        nonmutating _modify { yield &planState.planStreamingContentByConversation }
    }

    var planQuestionToolRequestEpoch: Int {
        get { planState.planQuestionToolRequestEpoch }
        nonmutating set { planState.planQuestionToolRequestEpoch = newValue }
    }

    var planShouldRunInline: Bool {
        get { planState.planShouldRunInline }
        nonmutating set { planState.planShouldRunInline = newValue }
    }

    var activeBuildPlanConversationId: UUID? {
        get { planState.activeBuildPlanConversationId }
        nonmutating set { planState.activeBuildPlanConversationId = newValue }
    }

    var activeBuildAgentConversationId: UUID? {
        get { planState.activeBuildAgentConversationId }
        nonmutating set { planState.activeBuildAgentConversationId = newValue }
    }

    var suppressedEmptyBuildAssistantMessageIds: Set<UUID> {
        get { planState.suppressedEmptyBuildAssistantMessageIds }
        nonmutating set { planState.suppressedEmptyBuildAssistantMessageIds = newValue }
        nonmutating _modify { yield &planState.suppressedEmptyBuildAssistantMessageIds }
    }

    var isPlanSummaryCollapsed: Bool {
        get { planState.isPlanSummaryCollapsed }
        nonmutating set { planState.isPlanSummaryCollapsed = newValue }
    }

    var isPlanTabHovered: Bool {
        get { planState.isPlanTabHovered }
        nonmutating set { planState.isPlanTabHovered = newValue }
    }

    var isPlanShortcutCycling: Bool {
        get { planState.isPlanShortcutCycling }
        nonmutating set { planState.isPlanShortcutCycling = newValue }
    }

    var inlinePlanSummaries: [UUID: InlinePlanSummary] {
        get { planState.inlinePlanSummaries }
        nonmutating set { planState.inlinePlanSummaries = newValue }
        nonmutating _modify { yield &planState.inlinePlanSummaries }
    }

    var planToggleEnabled: Bool {
        get { panelState.planToggleEnabled }
        nonmutating set { panelState.planToggleEnabled = newValue }
    }

    var debugToggleEnabled: Bool {
        get { panelState.debugToggleEnabled }
        nonmutating set { panelState.debugToggleEnabled = newValue }
    }

    var selectedSwarmId: String? {
        get { panelState.selectedSwarmId }
        nonmutating set { panelState.selectedSwarmId = newValue }
    }

    var planPanelPresentationSource: PlanPanelPresentationSource {
        get { panelState.planPanelPresentationSource }
        nonmutating set { panelState.planPanelPresentationSource = newValue }
    }

    var threadUIStateByConversation: [UUID: ChatThreadUIState] {
        get { panelState.threadUIStateByConversation }
        nonmutating set { panelState.threadUIStateByConversation = newValue }
        nonmutating _modify { yield &panelState.threadUIStateByConversation }
    }

    var isRestoringThreadUIState: Bool {
        get { panelState.isRestoringThreadUIState }
        nonmutating set { panelState.isRestoringThreadUIState = newValue }
    }

    var hasJustCompletedTask: Bool {
        get { panelState.hasJustCompletedTask }
        nonmutating set { panelState.hasJustCompletedTask = newValue }
    }

    var showRateLimitAlert: Bool {
        get { panelState.showRateLimitAlert }
        nonmutating set { panelState.showRateLimitAlert = newValue }
    }

    var rateLimitAlertText: String {
        get { panelState.rateLimitAlertText }
        nonmutating set { panelState.rateLimitAlertText = newValue }
    }

    var didCopyAllChat: Bool {
        get { panelState.didCopyAllChat }
        nonmutating set { panelState.didCopyAllChat = newValue }
    }

    var isFollowingLive: Bool {
        get { panelState.isFollowingLive }
        nonmutating set { panelState.isFollowingLive = newValue }
    }

    var newEventsWhileDetached: Int {
        get { panelState.newEventsWhileDetached }
        nonmutating set { panelState.newEventsWhileDetached = newValue }
    }

    var chatHeaderWidth: CGFloat {
        get { panelState.chatHeaderWidth }
        nonmutating set { panelState.chatHeaderWidth = newValue }
    }

    var isProviderReady: Bool {
        get { interactionState.isProviderReady }
        nonmutating set { interactionState.isProviderReady = newValue }
    }

    var isSummarizing: Bool {
        get { interactionState.isSummarizing }
        nonmutating set { interactionState.isSummarizing = newValue }
    }

    var isRewinding: Bool {
        get { interactionState.isRewinding }
        nonmutating set { interactionState.isRewinding = newValue }
    }

    var isPlanBuildCheckpointInFlight: Bool {
        get { interactionState.isPlanBuildCheckpointInFlight }
        nonmutating set { interactionState.isPlanBuildCheckpointInFlight = newValue }
    }

    var isAnyAgentProviderReady: Bool {
        get { interactionState.isAnyAgentProviderReady }
        nonmutating set { interactionState.isAnyAgentProviderReady = newValue }
    }

    var checkProviderAuthGeneration: Int {
        get { interactionState.checkProviderAuthGeneration }
        nonmutating set { interactionState.checkProviderAuthGeneration = newValue }
    }

    var userModeOverrideUntilConversationChange: Bool {
        get { interactionState.userModeOverrideUntilConversationChange }
        nonmutating set { interactionState.userModeOverrideUntilConversationChange = newValue }
    }

    var suppressModeSyncForNextProviderChange: Bool {
        get { interactionState.suppressModeSyncForNextProviderChange }
        nonmutating set { interactionState.suppressModeSyncForNextProviderChange = newValue }
    }

    var ignoreNextConversationChangeReset: Bool {
        get { interactionState.ignoreNextConversationChangeReset }
        nonmutating set { interactionState.ignoreNextConversationChangeReset = newValue }
    }

    var skipNextLoadingCompletedHandling: Bool {
        get { interactionState.skipNextLoadingCompletedHandling }
        nonmutating set { interactionState.skipNextLoadingCompletedHandling = newValue }
    }
}
