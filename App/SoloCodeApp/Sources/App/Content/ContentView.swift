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
    @EnvironmentObject var toolTraceStore: ToolTraceStore
    @EnvironmentObject var gitPanelStore: GitPanelStore
    @EnvironmentObject var planHistoryStore: PlanHistoryStore
    @EnvironmentObject var pipelineIntegrationService: PipelineIntegrationService
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

    // MARK: - Centralized Panel State

    @StateObject var panelCoordinator = UIPanelCoordinator()

    // MARK: - Layout AppStorage

    @AppStorage("chat_background_style") var chatBackgroundStyle = ChatBackgroundStyle.defaultRawValue
    @AppStorage("ide_workbench_sidebar_visible") var showIDEWorkbenchSidebar = true
    @AppStorage("git_panel_width") var gitPanelWidth: Double = 380
    @AppStorage("chat_panel_width") var chatPanelWidth: Double = 380
    @AppStorage("side_panel_width") var sidePanelWidth: Double = 240
    @AppStorage("auto_resize_side_panels") var autoResizeSidePanels = false
    @AppStorage("chat_panel_position") var chatPanelPosition = "left"
    @AppStorage("browser_panel_width") var browserPanelWidth: Double = 500

    var body: some View {
        configuredContent
            .navigationTitle("")
            .hideSidebarToggleIfSupported()
            .overlay(alignment: .topLeading) {
                alwaysVisibleWindowChrome
            }
            .onReceive(NotificationCenter.default.publisher(for: .windowSidebarChromeToggleRequested)) { _ in
                handleWindowSidebarChromeToggle()
            }
    }

    private var alwaysVisibleWindowChrome: some View {
        WindowChromeControls(showTrafficLights: showsWindowTrafficLights)
            .padding(.leading, 14)
            .padding(.top, -21)
            .allowsHitTesting(true)
    }

    private var showsWindowTrafficLights: Bool {
        switch panelCoordinator.coderMode {
        case .ide:
            return showIDEWorkbenchSidebar
        case .browser:
            return false
        default:
            return panelCoordinator.columnVisibility != .detailOnly
        }
    }
}
