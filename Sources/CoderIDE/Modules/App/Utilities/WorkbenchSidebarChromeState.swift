import Foundation

extension Notification.Name {
    static let workbenchSidebarToggleRequested =
        Notification.Name("CodigoWorkbenchSidebarToggleRequested")
    static let workbenchSidebarChromeStateDidChange =
        Notification.Name("CodigoWorkbenchSidebarChromeStateDidChange")
}

struct WorkbenchSidebarChromeState {
    private enum Key {
        static let isAvailable = "isAvailable"
        static let isVisible = "isVisible"
    }

    let isAvailable: Bool
    let isVisible: Bool

    var userInfo: [AnyHashable: Any] {
        [
            Key.isAvailable: isAvailable,
            Key.isVisible: isVisible,
        ]
    }

    init(isAvailable: Bool, isVisible: Bool) {
        self.isAvailable = isAvailable
        self.isVisible = isVisible
    }

    init?(userInfo: [AnyHashable: Any]?) {
        guard
            let userInfo,
            let isAvailable = userInfo[Key.isAvailable] as? Bool,
            let isVisible = userInfo[Key.isVisible] as? Bool
        else {
            return nil
        }

        self.init(isAvailable: isAvailable, isVisible: isVisible)
    }
}
