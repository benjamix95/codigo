import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func handleMessagesViewportChange(isNearBottom: Bool) {
        if scrollState.pendingProgrammaticViewportObservations > 0 {
            scrollState.pendingProgrammaticViewportObservations -= 1
            return
        }

        let nextValue = ChatAutoScrollFollowPolicy.updatedIsFollowingLive(
            currentValue: isFollowingLive,
            isNearBottom: isNearBottom,
            isConversationBusy: isLoadingForCurrentConversation || snapshotIsLoading,
            secondsSinceProgrammaticScroll: Date().timeIntervalSince(scrollState.lastProgrammaticScrollAt)
        )
        guard nextValue != isFollowingLive else { return }

        isFollowingLive = nextValue
        if nextValue {
            newEventsWhileDetached = 0
        }
    }
}
