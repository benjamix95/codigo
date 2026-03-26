import Foundation
import SwiftUI
import CoderEngine

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
    var showNoProjectOpenAlert = false
    var didCopyAllChat = false
    var isFollowingLive = true
    var newEventsWhileDetached = 0
    var chatHeaderWidth: CGFloat = 800
}

struct ChatPanelInteractionViewState {
    var isProviderReady = false
    var isSummarizing = false
    var isRewinding = false
    var isPlanBuildCheckpointInFlight = false
    var isAnyAgentProviderReady = false
    var checkProviderAuthGeneration = 0
    var userModeOverrideUntilConversationChange = false
    var suppressModeSyncForNextProviderChange = false
    var ignoreNextConversationChangeReset = false
    var skipNextLoadingCompletedHandling = false
}
