import SwiftUI

extension ChatPanelView {
    var planInPanelPlaceholder: String {
        "Plan available in the Plan Panel."
    }

    var shouldShowPlanTodosInChat: Bool {
        let hasSwarmSteps = !swarmProgressStore.steps(for: conversationId).isEmpty
        let hasLiveSwarmCards = !taskActivityStore.swarmCardStates(for: conversationId).isEmpty
        let hasPipelineProgress = pipelineIntegrationService.isRunning(for: conversationId)
        return !(hasSwarmSteps || hasLiveSwarmCards || hasPipelineProgress)
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
