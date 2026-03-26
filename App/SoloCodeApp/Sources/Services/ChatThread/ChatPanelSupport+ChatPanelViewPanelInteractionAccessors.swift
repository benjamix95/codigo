import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
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

    var showNoProjectOpenAlert: Bool {
        get { panelState.showNoProjectOpenAlert }
        nonmutating set { panelState.showNoProjectOpenAlert = newValue }
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
