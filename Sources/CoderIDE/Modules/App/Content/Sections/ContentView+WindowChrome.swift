import SwiftUI

extension ContentView {
    func toggleWorkbenchSidebarFromWindowChrome() {
        withAnimation(.snappy(duration: 0.2)) {
            activeActivityItem = SidebarToggleState.nextSelection(
                current: activeActivityItem,
                lastVisible: lastSidebarActivityItem
            )
        }
    }

    func rememberLastVisibleSidebar(_ item: ActivityBarItem?) {
        lastSidebarActivityItem = SidebarToggleState.updatedLastVisible(
            current: item,
            previous: lastSidebarActivityItem
        )
    }

    func publishWorkbenchSidebarChromeState() {
        let state = WorkbenchSidebarChromeState(
            isAvailable: coderMode == .ide,
            isVisible: activeActivityItem != nil
        )
        NotificationCenter.default.post(
            name: .workbenchSidebarChromeStateDidChange,
            object: nil,
            userInfo: state.userInfo
        )
    }
}
