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
    @State var isSelectingAddFolder = false
    @State var pendingAddFolderContextId: UUID?
    @State var activeActivityItem: ActivityBarItem? = .explorer
    @State var showChatPanel = true
    @State var coderMode: CoderMode = .agent

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
        switch coderMode {
        case .ide:
            return showIDEWorkbenchSidebar
        case .browser:
            return false
        default:
            return columnVisibility != .detailOnly
        }
    }
}

private struct WindowChromeControls: View {
    let showTrafficLights: Bool
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var hoveredControl: WindowControlKind?

    var body: some View {
        HStack(spacing: 8) {
            if showTrafficLights {
                ForEach(WindowControlKind.allCases, id: \.self) { kind in
                    Button {
                        performWindowAction(kind)
                    } label: {
                        Circle()
                            .fill(kind.fillColor(active: controlActiveState != .inactive))
                            .frame(width: 13, height: 13)
                            .overlay {
                                if hoveredControl == kind {
                                    Image(systemName: kind.symbolName)
                                        .font(.system(size: 6.5, weight: .bold))
                                        .foregroundStyle(.black.opacity(0.72))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(kind.helpText)
                    .accessibilityLabel(kind.helpText)
                    .onHover { isHovering in
                        hoveredControl = isHovering ? kind : (hoveredControl == kind ? nil : hoveredControl)
                    }
                }
            }

            Button {
                NotificationCenter.default.post(name: .windowSidebarChromeToggleRequested, object: nil)
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        DesignSystem.Colors.textPrimary.opacity(controlActiveState == .inactive ? 0.6 : 0.96)
                    )
                    .frame(width: 30, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(controlActiveState == .inactive ? 0.05 : 0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(DesignSystem.Colors.borderSubtle.opacity(0.9), lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle Sidebar")
            .accessibilityLabel("Toggle Sidebar")
        }
        .frame(height: 24)
    }

    private func performWindowAction(_ kind: WindowControlKind) {
        guard let window = NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first(where: { $0.canBecomeMain }) else { return }

        switch kind {
        case .close:
            window.performClose(nil)
        case .minimize:
            window.miniaturize(nil)
        case .zoom:
            window.performZoom(nil)
        }
    }
}

private enum WindowControlKind: CaseIterable {
    case close
    case minimize
    case zoom

    var symbolName: String {
        switch self {
        case .close:
            return "xmark"
        case .minimize:
            return "minus"
        case .zoom:
            return "plus"
        }
    }

    var helpText: String {
        switch self {
        case .close:
            return "Close Window"
        case .minimize:
            return "Minimize Window"
        case .zoom:
            return "Zoom Window"
        }
    }

    func fillColor(active: Bool) -> Color {
        switch self {
        case .close:
            return Color(red: 1.0, green: 0.37, blue: 0.33).opacity(active ? 1 : 0.6)
        case .minimize:
            return Color(red: 0.98, green: 0.79, blue: 0.26).opacity(active ? 1 : 0.6)
        case .zoom:
            return Color(red: 0.16, green: 0.84, blue: 0.31).opacity(active ? 1 : 0.6)
        }
    }
}
