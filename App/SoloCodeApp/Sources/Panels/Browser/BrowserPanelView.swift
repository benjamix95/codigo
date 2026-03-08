import SwiftUI

// MARK: - Browser Panel View

struct BrowserPanelView: View {
    @ObservedObject var tabManager: BrowserTabManager
    @State var urlFieldText: String = ""
    @State var consoleFilterLevel: ConsoleLogLevel? = nil
    @AppStorage("browser_console_height") var consoleHeight: Double = 180
    let topInteractiveInset: CGFloat = 28

    var activeStore: BrowserSessionStore? { tabManager.activeStore }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topInteractiveInset)
                .allowsHitTesting(false)
            browserTabBar
            Divider().opacity(0.2)
            browserToolbar
            Divider().opacity(0.2)
            browserContent
        }
        .background(DesignSystem.Colors.backgroundDeep)
    }
}
