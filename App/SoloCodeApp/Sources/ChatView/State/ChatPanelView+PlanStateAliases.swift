import Foundation

// MARK: - ChatPanelView Plan State Aliases

/// Computed property aliases that forward to `planState` (ChatPlanUIState).
/// These maintain backward compatibility with the 30+ extension files
/// that reference `self.planFlowPhase`, `self.planningState`, etc.
///
/// Once all extensions are migrated to use `planState.xyz` directly,
/// these aliases can be removed.
extension ChatPanelView {
    var planFlowPhase: PlanFlowPhase {
        get { planState.flowPhase }
        nonmutating set { planState.flowPhase = newValue }
    }

    var planningState: PlanningState {
        get { planState.planningState }
        nonmutating set { planState.planningState = newValue }
    }

    var planAnalysisContext: String {
        get { planState.analysisContext }
        nonmutating set { planState.analysisContext = newValue }
    }

    var planUserRequest: String {
        get { planState.userRequest }
        nonmutating set { planState.userRequest = newValue }
    }

    var planClarificationAnswers: String {
        get { planState.clarificationAnswers }
        nonmutating set { planState.clarificationAnswers = newValue }
    }

    var planClarificationQuestionnaire: PlanClarificationQuestionnaire? {
        get { planState.clarificationQuestionnaire }
        nonmutating set { planState.clarificationQuestionnaire = newValue }
    }

    var planClarificationCycles: Int {
        get { planState.clarificationCycles }
        nonmutating set { planState.clarificationCycles = newValue }
    }

    var planStreamingContent: String {
        get { planState.streamingContent }
        nonmutating set { planState.streamingContent = newValue }
    }

    var planStreamingContentByConversation: [UUID: String] {
        get { planState.streamingContentByConversation }
        nonmutating set { planState.streamingContentByConversation = newValue }
    }

    var planQuestionToolRequestEpoch: Int {
        get { planState.questionToolRequestEpoch }
        nonmutating set { planState.questionToolRequestEpoch = newValue }
    }

    var planShouldRunInline: Bool {
        get { planState.shouldRunInline }
        nonmutating set { planState.shouldRunInline = newValue }
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
    }

    var isPlanSummaryCollapsed: Bool {
        get { planState.isSummaryCollapsed }
        nonmutating set { planState.isSummaryCollapsed = newValue }
    }

    var isPlanTabHovered: Bool {
        get { planState.isTabHovered }
        nonmutating set { planState.isTabHovered = newValue }
    }

    var isPlanShortcutCycling: Bool {
        get { planState.isShortcutCycling }
        nonmutating set { planState.isShortcutCycling = newValue }
    }

    var inlinePlanSummaries: [UUID: InlinePlanSummary] {
        get { planState.inlineSummaries }
        nonmutating set { planState.inlineSummaries = newValue }
    }

    var planPanelPresentationSource: PlanPanelPresentationSource {
        get { planState.panelPresentationSource }
        nonmutating set { planState.panelPresentationSource = newValue }
    }

    var pendingPlanStreamingContent: String? {
        get { planState.pendingStreamingContent }
        nonmutating set { planState.pendingStreamingContent = newValue }
    }

    var pendingPlanStreamConversationId: UUID? {
        get { planState.pendingStreamConversationId }
        nonmutating set { planState.pendingStreamConversationId = newValue }
    }

    var planStreamThrottleTask: Task<Void, Never>? {
        get { planState.streamThrottleTask }
        nonmutating set { planState.streamThrottleTask = newValue }
    }
}
