import SwiftUI

extension ContentView {
    func handleWindowSidebarChromeToggle() {
        switch coderMode {
        case .ide, .browser:
            withAnimation(.snappy(duration: 0.2)) {
                showChatPanel.toggle()
            }
        default:
            withAnimation(.snappy(duration: 0.2)) {
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
            }
        }
    }
}
