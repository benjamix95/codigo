import Foundation
import SwiftUI

// MARK: - ChatPlanUIState

/// ObservableObject state container for plan-related UI properties.
/// Extracted from ChatPanelView to reduce @State explosion and isolate re-renders.
/// Uses ObservableObject (not @Observable) for macOS 13.0 compatibility.
@MainActor
final class ChatPlanUIState: ObservableObject {
    @Published var planningState: PlanningState = .idle
    @Published var flowPhase: PlanFlowPhase = .idle
    @Published var analysisContext: String = ""
    @Published var userRequest: String = ""
    @Published var clarificationAnswers: String = ""
    @Published var clarificationQuestionnaire: PlanClarificationQuestionnaire?
    @Published var clarificationCycles: Int = 0
    @Published var streamingContent: String = ""
    @Published var streamingContentByConversation: [UUID: String] = [:]
    @Published var questionToolRequestEpoch: Int = 0
    @Published var shouldRunInline: Bool = false
    @Published var activeBuildPlanConversationId: UUID?
    @Published var activeBuildAgentConversationId: UUID?
    @Published var suppressedEmptyBuildAssistantMessageIds: Set<UUID> = []
    @Published var isSummaryCollapsed: Bool = false
    @Published var isTabHovered: Bool = false
    @Published var isShortcutCycling: Bool = false
    @Published var inlineSummaries: [UUID: InlinePlanSummary] = [:]
    @Published var panelPresentationSource: PlanPanelPresentationSource = .manualDeepLink
    @Published var pendingStreamingContent: String?
    @Published var pendingStreamConversationId: UUID?
    var streamThrottleTask: Task<Void, Never>?

    /// Resets all plan state to idle defaults.
    func reset() {
        planningState = .idle
        flowPhase = .idle
        analysisContext = ""
        userRequest = ""
        clarificationAnswers = ""
        clarificationQuestionnaire = nil
        clarificationCycles = 0
        streamingContent = ""
        questionToolRequestEpoch = 0
        shouldRunInline = false
        isSummaryCollapsed = false
        isTabHovered = false
        isShortcutCycling = false
        pendingStreamingContent = nil
        pendingStreamConversationId = nil
        streamThrottleTask?.cancel()
        streamThrottleTask = nil
    }
}
