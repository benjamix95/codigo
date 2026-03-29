import CoreGraphics
import Foundation

enum ChatAutoScrollFollowPolicy {
    static let bottomFollowDistanceThreshold: CGFloat = 72
    static let programmaticScrollGraceInterval: TimeInterval = 0.18

    static func updatedIsFollowingLive(
        currentValue: Bool,
        isNearBottom: Bool,
        isConversationBusy: Bool,
        secondsSinceProgrammaticScroll: TimeInterval
    ) -> Bool {
        if isNearBottom {
            return true
        }
        if secondsSinceProgrammaticScroll < programmaticScrollGraceInterval {
            return currentValue
        }
        if currentValue, isConversationBusy {
            return false
        }
        return currentValue
    }
}
