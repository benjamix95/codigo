import SwiftUI

extension ChatPanelView {
    @MainActor
    internal func requestInitialComposerFocusIfNeeded() {
        guard !didAutoFocusComposerOnLaunch else { return }
        guard selectedConversationId != nil else { return }
        didAutoFocusComposerOnLaunch = true
        composerAutoFocusTask?.cancel()
        composerAutoFocusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            isInputFocused = true
        }
    }

    var planInPanelPlaceholder: String {
        "Plan available in the Plan Panel."
    }

    var shouldShowPlanTodosInChat: Bool {
        let hasSwarmSteps = !swarmProgressStore.steps(for: conversationId).isEmpty
        let hasLiveSwarmCards = !taskActivityStore.swarmCardStates(for: conversationId).isEmpty
        let hasPipelineProgress = pipelineIntegrationService.isRunning(for: conversationId)
        return shouldShowLiveTodoCardInChat(
            hasSwarmSteps: hasSwarmSteps,
            hasLiveSwarmCards: hasLiveSwarmCards,
            hasPipelineProgress: hasPipelineProgress
        )
    }

    var shouldRoutePlanStreamingToPanel: Bool {
        false
    }

    var shouldShowPlanBoardInChat: Bool {
        false
    }

    var shouldShowInlinePlanSummaryInChat: Bool {
        false
    }

    var shouldShowPlanAttachmentsInChat: Bool {
        false
    }

    var hasActivePlanFlowPhase: Bool {
        planFlowPhase == .analyzing
            || planFlowPhase == .questioning
            || planFlowPhase == .generating
            || planFlowPhase == .proposalReady
            || planFlowPhase == .readyToBuild
            || planFlowPhase == .building
    }
}
