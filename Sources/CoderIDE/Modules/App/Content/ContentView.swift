import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoderEngine

struct ContentView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var projectContextStore: ProjectContextStore
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @EnvironmentObject var executionController: ExecutionController
    @EnvironmentObject var providerUsageStore: ProviderUsageStore
    @EnvironmentObject var todoStore: TodoStore
    @EnvironmentObject var taskActivityStore: TaskActivityStore
    @EnvironmentObject var gitPanelStore: GitPanelStore
    @EnvironmentObject var planHistoryStore: PlanHistoryStore
    @EnvironmentObject var appUpdateCenter: AppUpdateCenter
    @StateObject var editorSplitStore = EditorSplitStore()
    @StateObject var editorPanelsStore = EditorPanelsStore()
    @StateObject var editorQuickOpenStore = EditorQuickOpenStore()
    @StateObject var editorDiagnosticsStore = EditorDiagnosticsStore()
    @StateObject var editorSymbolsStore = EditorSymbolsStore()
    @StateObject var editorCommandDispatchStore = EditorCommandDispatchStore()
    @StateObject var editorNavigationDispatchStore = EditorNavigationDispatchStore()
    @StateObject var debugStore = DebugStore()
    @StateObject var terminalSessionStore = TerminalSessionStore()
    @StateObject var browserTabManager = BrowserTabManager()
    @State var selectedConversationId: UUID?
    @State var columnVisibility: NavigationSplitViewVisibility = .all
    @State var showTerminal = false
    @State var terminalHeight: CGFloat = 200
    @State var preferActiveContextForGlobalThread = true
    @State var showSettings = false
    @State var showPlanPanel = false
    @State var showDebugPanel = false
    @State var showSwarmPanel = false
    @State var showCodeReviewPanel = false
    @State var showBrowserPanel = false
    @State var showAppUpdateAlert = false
    @State var pendingAppUpdate: AppUpdateCenter.AppUpdateManifest?
    @State var isSelectingProjectFolders = false
    @State var activeActivityItem: ActivityBarItem? = .explorer
    @State var showChatPanel = true
    @State var coderMode: CoderMode = .agent

    @AppStorage("chat_background_style") var chatBackgroundStyle = ChatBackgroundStyle.defaultRawValue
    @AppStorage("git_panel_width") var gitPanelWidth: Double = 380
    @AppStorage("chat_panel_width") var chatPanelWidth: Double = 380
    @AppStorage("side_panel_width") var sidePanelWidth: Double = 240
    @AppStorage("auto_resize_side_panels") var autoResizeSidePanels = false
    @AppStorage("chat_panel_position") var chatPanelPosition = "left"
    @AppStorage("browser_panel_width") var browserPanelWidth: Double = 500

    var body: some View {
        configuredContent
            .navigationTitle("")
            .toolbar(removing: .sidebarToggle)
            .toolbar(.hidden, for: .windowToolbar)
            .toolbar(.hidden, for: .automatic)
            .onChange(of: columnVisibility) { _, _ in
                DispatchQueue.main.async {
                    for window in NSApplication.shared.windows where window.canBecomeMain {
                        AppDelegate.applyMainWindowStyle(window)
                    }
                }
                // SwiftUI may re-add the native sidebar toggle after columnVisibility changes;
                // strip again after layout settles — extended delays for IDE mode transitions.
                for delay in [0.1, 0.3, 0.6, 1.0, 1.5] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        for window in NSApplication.shared.windows where window.canBecomeMain {
                            AppDelegate.applyMainWindowStyle(window)
                        }
                    }
                }
            }
    }
}
