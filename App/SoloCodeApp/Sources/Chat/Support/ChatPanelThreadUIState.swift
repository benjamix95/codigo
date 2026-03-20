import Foundation

enum ChatBackgroundStyle: String, CaseIterable, Identifiable {
    case solidNeutral = "solid_neutral"
    case transparentLegacy = "transparent_legacy"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solidNeutral: return "Solido neutro"
        case .transparentLegacy: return "Trasparente"
        }
    }

    static var defaultRawValue: String { ChatBackgroundStyle.solidNeutral.rawValue }

    static func normalizedRawValue(_ raw: String) -> String {
        ChatBackgroundStyle(rawValue: raw)?.rawValue ?? defaultRawValue
    }

    static func from(raw: String) -> ChatBackgroundStyle {
        ChatBackgroundStyle(rawValue: raw) ?? .solidNeutral
    }
}

enum ChatThreadInspectorPanel: String {
    case plan
    case debug
    case swarm
    case codeReview
}

struct ChatThreadUIState {
    let activeInspectorPanel: ChatThreadInspectorPanel?
    let planToggleEnabled: Bool
    let debugToggleEnabled: Bool
    let showBrowserPanel: Bool
    let showGitPanel: Bool
    let selectedSwarmId: String?
    let planPanelPresentationSource: PlanPanelPresentationSource
}

func shouldStartThreadWithCleanUIState(
    hasPersistedUIState: Bool,
    hasUserMessages: Bool
) -> Bool {
    !hasPersistedUIState && !hasUserMessages
}

extension ChatPanelView {
    @MainActor
    internal func persistThreadUIState(for conversationId: UUID?) {
        guard let conversationId else { return }
        threadUIStateByConversation[conversationId] = currentThreadUIState()
    }

    @MainActor
    internal func restoreThreadUIState(for conversationId: UUID?) {
        let restoredState = conversationId.flatMap { threadUIStateByConversation[$0] }
            ?? defaultThreadUIState(for: conversationId)
        applyThreadUIState(restoredState)
    }

    @MainActor
    internal func currentThreadUIState() -> ChatThreadUIState {
        ChatThreadUIState(
            activeInspectorPanel: activeInspectorPanel,
            planToggleEnabled: planToggleEnabled,
            debugToggleEnabled: debugToggleEnabled,
            showBrowserPanel: showBrowserPanel,
            showGitPanel: gitPanelStore.isOpen,
            selectedSwarmId: selectedSwarmId,
            planPanelPresentationSource: planPanelPresentationSource
        )
    }

    @MainActor
    internal func defaultThreadUIState(for conversationId: UUID?) -> ChatThreadUIState {
        guard let conversationId else {
            return emptyThreadUIState()
        }

        let hasPersistedUIState = threadUIStateByConversation[conversationId] != nil
        let hasUserMessages = chatStore.conversation(for: conversationId).map(chatStore.hasUserMessages) ?? false
        if shouldStartThreadWithCleanUIState(
            hasPersistedUIState: hasPersistedUIState,
            hasUserMessages: hasUserMessages
        ) {
            return emptyThreadUIState()
        }

        let shouldShowDebug = coderMode == .debug || debugStore.phase.isActive
        let hasPlanExecutionInForeground = isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        ) || hasActivePlanFlowPhase
        let shouldShowPlan = !shouldShowDebug && (coderMode == .plan || hasPlanExecutionInForeground)
        let shouldShowBrowser = coderMode == .browser

        let activePanel: ChatThreadInspectorPanel? = {
            if shouldShowDebug { return .debug }
            if shouldShowPlan { return .plan }
            return nil
        }()

        return ChatThreadUIState(
            activeInspectorPanel: activePanel,
            planToggleEnabled: shouldShowPlan,
            debugToggleEnabled: shouldShowDebug,
            showBrowserPanel: shouldShowBrowser,
            showGitPanel: false,
            selectedSwarmId: nil,
            planPanelPresentationSource: .manualDeepLink
        )
    }

    @MainActor
    internal func emptyThreadUIState() -> ChatThreadUIState {
        ChatThreadUIState(
            activeInspectorPanel: nil,
            planToggleEnabled: false,
            debugToggleEnabled: false,
            showBrowserPanel: false,
            showGitPanel: false,
            selectedSwarmId: nil,
            planPanelPresentationSource: .manualDeepLink
        )
    }

    @MainActor
    internal var activeInspectorPanel: ChatThreadInspectorPanel? {
        if showDebugPanel { return .debug }
        if showPlanPanel { return .plan }
        if showSwarmPanel { return .swarm }
        if showCodeReviewPanel { return .codeReview }
        return nil
    }

    @MainActor
    internal func applyThreadUIState(_ state: ChatThreadUIState) {
        isRestoringThreadUIState = true

        let activePanel = state.activeInspectorPanel
        showPlanPanel = activePanel == .plan
        showDebugPanel = activePanel == .debug
        showSwarmPanel = activePanel == .swarm
        showCodeReviewPanel = activePanel == .codeReview

        planPanelPresentationSource = state.planPanelPresentationSource
        showBrowserPanel = state.showBrowserPanel
        gitPanelStore.isOpen = state.showGitPanel
        selectedSwarmId = state.selectedSwarmId
        planToggleEnabled = state.planToggleEnabled
        debugToggleEnabled = state.debugToggleEnabled

        isRestoringThreadUIState = false
    }
}
