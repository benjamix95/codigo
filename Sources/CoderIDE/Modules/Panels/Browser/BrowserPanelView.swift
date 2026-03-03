import SwiftUI

// MARK: - Browser Panel View

struct BrowserPanelView: View {
    @ObservedObject var tabManager: BrowserTabManager
    @State private var urlFieldText: String = ""
    @State private var consoleFilterLevel: ConsoleLogLevel? = nil
    @AppStorage("browser_console_height") private var consoleHeight: Double = 180

    private var activeStore: BrowserSessionStore? { tabManager.activeStore }

    var body: some View {
        VStack(spacing: 0) {
            browserTabBar
            Divider().opacity(0.2)
            browserToolbar
            Divider().opacity(0.2)
            browserContent
        }
        .background(DesignSystem.Colors.backgroundDeep)
    }
}
