import SwiftUI

extension ContentView {
    func handleWindowSidebarChromeToggle() {
        switch coderMode {
        case .ide:
            withAnimation(.snappy(duration: 0.2)) {
                showIDEWorkbenchSidebar.toggle()
            }
        case .browser:
            withAnimation(.snappy(duration: 0.2)) {
                showBrowserPanel.toggle()
            }
        default:
            withAnimation(.snappy(duration: 0.2)) {
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
            }
        }
    }
}
