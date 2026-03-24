import SwiftUI

extension ContentView {
    func handleWindowSidebarChromeToggle() {
        switch panelCoordinator.coderMode {
        case .ide:
            withAnimation(.snappy(duration: 0.2)) {
                showIDEWorkbenchSidebar.toggle()
            }
        case .browser:
            withAnimation(.snappy(duration: 0.2)) {
                panelCoordinator.showBrowserPanel.toggle()
            }
        default:
            withAnimation(.snappy(duration: 0.2)) {
                panelCoordinator.columnVisibility = panelCoordinator.columnVisibility == .all ? .detailOnly : .all
            }
        }
    }
}
