import Foundation

enum ChatFinalActionsPlacementPolicy {
    static func shouldRenderBelowMessages(
        shouldShowFinalChatActions: Bool,
        showsSwarmViewOnly: Bool
    ) -> Bool {
        shouldShowFinalChatActions && !showsSwarmViewOnly
    }
}
