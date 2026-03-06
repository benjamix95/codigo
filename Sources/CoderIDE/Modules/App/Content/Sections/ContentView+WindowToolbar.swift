import SwiftUI

extension ContentView {
    @ToolbarContentBuilder
    var windowToolbarContent: some ToolbarContent {
        if coderMode == .ide {
            ToolbarItem(id: "workbench-sidebar-toggle", placement: .navigation) {
                Button(action: toggleWorkbenchSidebarFromTitlebar) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .help(activeActivityItem == nil ? "Show Sidebar" : "Hide Sidebar")
            }
        }
    }

    func toggleWorkbenchSidebarFromTitlebar() {
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
}
