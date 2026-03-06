import Foundation

enum SidebarToggleState {
    static func nextSelection(
        current: ActivityBarItem?,
        lastVisible: ActivityBarItem?
    ) -> ActivityBarItem? {
        guard current == nil else { return nil }
        return lastVisible ?? .explorer
    }

    static func updatedLastVisible(
        current: ActivityBarItem?,
        previous: ActivityBarItem
    ) -> ActivityBarItem {
        guard let current, current != .settings else { return previous }
        return current
    }
}
