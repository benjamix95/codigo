import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

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

    var lastTaskCompletionOutcome: ToolTraceTurnOutcome? {
        get { composerState.lastTaskCompletionOutcome }
        nonmutating set { composerState.lastTaskCompletionOutcome = newValue }
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
}
