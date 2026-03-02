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
    @StateObject private var debugStore = DebugStore()
    @StateObject private var terminalSessionStore = TerminalSessionStore()
    @StateObject private var browserTabManager = BrowserTabManager()
    @State private var selectedConversationId: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showTerminal = false
    @State private var terminalHeight: CGFloat = 200
    @State private var showSettings = false
    @State private var showPlanPanel = false
    @State private var showDebugPanel = false
    @State private var showSwarmPanel = false
    @State private var showCodeReviewPanel = false
    @State private var showBrowserPanel = false
    @State private var showAppUpdateAlert = false
    @State private var pendingAppUpdate: AppUpdateCenter.AppUpdateManifest?
    @State private var isSelectingProjectFolders = false
    @State private var activeActivityItem: ActivityBarItem? = .explorer
    @State private var showChatPanel = true
    @State private var coderMode: CoderMode = .agent
    @AppStorage("chat_background_style") private var chatBackgroundStyle = ChatBackgroundStyle.defaultRawValue
    @AppStorage("git_panel_width") private var gitPanelWidth: Double = 380
    @AppStorage("chat_panel_width") private var chatPanelWidth: Double = 380
    @AppStorage("side_panel_width") private var sidePanelWidth: Double = 240
    @AppStorage("auto_resize_side_panels") private var autoResizeSidePanels = false
    @AppStorage("chat_panel_position") private var chatPanelPosition = "left"
    @AppStorage("browser_panel_width") private var browserPanelWidth: Double = 500

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selectedConversationId: $selectedConversationId,
                showSettings: $showSettings,
                isSelectingProjectFolders: $isSelectingProjectFolders
            )
            .environmentObject(providerRegistry)
            .environmentObject(chatStore)
            .environmentObject(workspaceStore)
            .environmentObject(projectContextStore)
            .environmentObject(openFilesStore)
            .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 320)
        } detail: {
            GeometryReader { geo in
                let detailWidth = geo.size.width
                let maxChatW = max(300, detailWidth * 0.45)
                let clampedChatW = min(CGFloat(chatPanelWidth), maxChatW)

                HStack(spacing: 0) {
                    let chatIsLeft = chatPanelPosition == "left"
                    let isIDEMode = coderMode == .ide

                    if isIDEMode {
                        // --- IDE MODE LAYOUT ---

                        // Activity Bar
                        ActivityBarView(
                            selectedItem: $activeActivityItem,
                            showSettings: $showSettings
                        )

                        // Chat Panel (left side, if configured)
                        if showChatPanel && chatIsLeft {
                            chatPanel
                                .frame(width: clampedChatW)

                            PanelResizeHandle(
                                panelWidth: Binding(
                                    get: { clampedChatW },
                                    set: { chatPanelWidth = Double($0) }
                                ),
                                minWidth: 300,
                                maxWidth: maxChatW,
                                leadingEdge: false
                            )
                        }

                        // Side Panel (Explorer / Search / Source Control)
                        if let item = activeActivityItem, item != .settings {
                            let ctx = effectiveContext(
                                for: selectedConversationId,
                                chatStore: chatStore,
                                projectContextStore: projectContextStore
                            )
                            SidePanelView(
                                activeItem: item,
                                context: projectContextStore.context(id: ctx.contextId)
                            )
                            .environmentObject(openFilesStore)
                            .environmentObject(projectContextStore)
                            .environmentObject(gitPanelStore)
                            .frame(width: max(180, min(CGFloat(sidePanelWidth), 400)))

                            PanelResizeHandle(
                                panelWidth: Binding(
                                    get: { CGFloat(sidePanelWidth) },
                                    set: { sidePanelWidth = Double($0) }
                                ),
                                minWidth: 180,
                                maxWidth: 400,
                                leadingEdge: false
                            )
                        }

                        // Editor Area (main, takes priority)
                        editorArea
                            .layoutPriority(1)

                        // Browser Panel
                        if showBrowserPanel {
                            let maxBrowserW = max(300, detailWidth * 0.55)
                            let clampedBrowserW = min(CGFloat(browserPanelWidth), maxBrowserW)

                            PanelResizeHandle(
                                panelWidth: Binding(
                                    get: { clampedBrowserW },
                                    set: { browserPanelWidth = Double($0) }
                                ),
                                minWidth: 300,
                                maxWidth: maxBrowserW,
                                leadingEdge: true
                            )

                            BrowserPanelView(tabManager: browserTabManager)
                                .frame(width: clampedBrowserW)
                        }

                        // Chat Panel (right side, if configured)
                        if showChatPanel && !chatIsLeft {
                            PanelResizeHandle(
                                panelWidth: Binding(
                                    get: { clampedChatW },
                                    set: { chatPanelWidth = Double($0) }
                                ),
                                minWidth: 300,
                                maxWidth: maxChatW,
                                leadingEdge: true
                            )

                            chatPanel
                                .frame(width: clampedChatW)
                        }

                    } else if coderMode == .browser {
                        // --- BROWSER MODE LAYOUT ---
                        // Chat on the left, browser panel on the right
                        chatPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)

                        if showBrowserPanel {
                            let maxBrowserW = max(300, detailWidth * 0.65)
                            let clampedBrowserW = min(CGFloat(browserPanelWidth), maxBrowserW)

                            PanelResizeHandle(
                                panelWidth: Binding(
                                    get: { clampedBrowserW },
                                    set: { browserPanelWidth = Double($0) }
                                ),
                                minWidth: 300,
                                maxWidth: maxBrowserW,
                                leadingEdge: true
                            )

                            BrowserPanelView(tabManager: browserTabManager)
                                .frame(width: clampedBrowserW)
                        }
                    } else {
                        // --- AGENT MODE LAYOUT ---
                        // Chat fills the entire space, no editor/explorer/activity bar
                        chatPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 720)
            .background(DesignSystem.Colors.backgroundDeep)
            .ignoresSafeArea(.container, edges: .top)
        }
        .onAppear {
            guard selectedConversationId == nil else { return }
            let defaultContextId = projectContextStore.activeContextId ?? workspaceStore.activeWorkspaceId
            let ctx = projectContextStore.context(id: defaultContextId)
            let folderScope = (ctx?.kind == .workspace) ? ctx?.activeFolderPath : nil
            if let contextId = defaultContextId,
               let lastId = projectContextStore.lastActiveConversationId(contextId: contextId, folderPath: folderScope),
               let lastConv = chatStore.conversation(for: lastId),
               lastConv.contextId == contextId,
               !lastConv.isArchived {
                selectedConversationId = lastId
            } else {
                let reusableConversation = chatStore.conversations.first { conv in
                    !conv.isArchived
                        && conv.contextId == defaultContextId
                        && conv.contextFolderPath == folderScope
                        && (conv.mode == nil || conv.mode == .agent)
                }
                selectedConversationId = reusableConversation?.id ?? chatStore.createConversation(
                    contextId: defaultContextId,
                    contextFolderPath: folderScope,
                    mode: nil
                )
            }
            let agentConv = chatStore.conversation(for: selectedConversationId)
            let preferredProvider = agentConv?.preferredProviderId
            providerRegistry.selectedProviderId = ProviderSupport.firstHealthyAgentProviderIdWithCodexFallback(
                preferred: preferredProvider,
                registry: providerRegistry
            )
        }
        .fileImporter(isPresented: $isSelectingProjectFolders, allowedContentTypes: [.folder], allowsMultipleSelection: true, onCompletion: handleProjectFolderSelection)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(providerRegistry)
                .environmentObject(executionController)
                .environmentObject(providerUsageStore)
                .environmentObject(appUpdateCenter)
        }
        .onReceive(NotificationCenter.default.publisher(for: .coderOpenSettingsFromMenuBar)) { _ in
            showSettings = true
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .providersDidRegister)) { _ in
            let agentConv = chatStore.conversation(for: selectedConversationId)
            let preferredProvider = agentConv?.preferredProviderId
            providerRegistry.selectedProviderId = ProviderSupport.firstHealthyAgentProviderIdWithCodexFallback(
                preferred: preferredProvider,
                registry: providerRegistry
            )
        }
        .onReceive(appUpdateCenter.$availableUpdate.compactMap { $0 }) { update in
            pendingAppUpdate = update
            showAppUpdateAlert = true
        }
        .onChange(of: isSelectingProjectFolders) { _, isPresented in
            if isPresented { NSApp.activate(ignoringOtherApps: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: BrowserTabManager.browserShouldOpenNotification)) { _ in
            if !showBrowserPanel {
                withAnimation(.snappy(duration: 0.2)) { showBrowserPanel = true }
            }
        }
        .onChange(of: showPlanPanel) { _, isOpen in
            guard isOpen else { return }
            showDebugPanel = false; showSwarmPanel = false; showCodeReviewPanel = false
        }
        .onChange(of: showDebugPanel) { _, isOpen in
            guard isOpen else { return }
            showPlanPanel = false; showSwarmPanel = false; showCodeReviewPanel = false
        }
        .onChange(of: showSwarmPanel) { _, isOpen in
            guard isOpen else { return }
            showPlanPanel = false; showDebugPanel = false; showCodeReviewPanel = false
        }
        .onChange(of: showCodeReviewPanel) { _, isOpen in
            guard isOpen else { return }
            showPlanPanel = false; showDebugPanel = false; showSwarmPanel = false
        }
        .onChange(of: gitPanelStore.isOpen) { wasOpen, isOpen in
            guard autoResizeSidePanels else { return }
            let panelWidth = CGFloat(gitPanelWidth) + 12
            if isOpen && !wasOpen {
                WindowResizeHelper.adjustWidth(by: panelWidth, animate: false)
            } else if !isOpen && wasOpen {
                WindowResizeHelper.adjustWidth(by: -panelWidth, animate: false)
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .onChange(of: coderMode) { _, newMode in
            withAnimation(.snappy(duration: 0.2)) {
                columnVisibility = (newMode == .ide || newMode == .browser) ? .detailOnly : .all
            }
        }
        .onChange(of: chatStore.conversations.map(\.id)) { _, conversationIds in
            guard !conversationIds.isEmpty else {
                selectedConversationId = nil
                return
            }
            if let selectedConversationId, conversationIds.contains(selectedConversationId) {
                return
            }
            let defaultContextId = projectContextStore.activeContextId ?? workspaceStore.activeWorkspaceId
            let ctx = projectContextStore.context(id: defaultContextId)
            let folderScope = (ctx?.kind == .workspace) ? ctx?.activeFolderPath : nil
            let preferred = chatStore.conversations.first { conv in
                !conv.isArchived
                    && conv.contextId == defaultContextId
                    && conv.contextFolderPath == folderScope
            }?.id
            selectedConversationId = preferred ?? conversationIds.first
        }
        .onChange(of: projectContextStore.activeContextId) { _, newContextId in
            guard let newContextId else { return }
            if let selectedId = selectedConversationId,
                let selected = chatStore.conversation(for: selectedId),
                !selected.isArchived,
                selected.messages.isEmpty {
                return
            }
            let conv = chatStore.conversation(for: selectedConversationId)
            guard conv?.contextId != newContextId else { return }
            let ctx = projectContextStore.context(id: newContextId)
            let folderScope = (ctx?.kind == .workspace) ? ctx?.activeFolderPath : nil
            if let lastId = projectContextStore.lastActiveConversationId(contextId: newContextId, folderPath: folderScope),
               let lastConv = chatStore.conversation(for: lastId),
               lastConv.contextId == newContextId,
               !lastConv.isArchived,
               lastConv.messages.contains(where: { $0.role == .user }) {
                selectedConversationId = lastId
            } else {
                selectedConversationId = chatStore.createConversation(contextId: newContextId, contextFolderPath: folderScope)
            }
        }
        .alert(
            "Update Available",
            isPresented: $showAppUpdateAlert,
            presenting: pendingAppUpdate
        ) { update in
            if let downloadURL = update.downloadURL, !downloadURL.isEmpty {
                Button("Download Now") { openExternalURL(downloadURL) }
            }
            if let notesURL = update.releaseNotesURL, !notesURL.isEmpty {
                Button("View Release Notes") { openExternalURL(notesURL) }
            }
            Button("Dismiss") { }
        } message: { update in
            Text(update.shortNotes)
        }
    }

    private func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Editor Area

    private var editorArea: some View {
        let ctx = effectiveContext(
            for: selectedConversationId,
            chatStore: chatStore,
            projectContextStore: projectContextStore
        )

        return VStack(spacing: 0) {
            editorTopBar(ctx: ctx)
            Divider().opacity(0.2)

            EditorPlaceholderView(folderPaths: ctx.folderPaths)
                .environmentObject(openFilesStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showTerminal {
                Divider().opacity(0.2)
                TerminalPanelView(workingDirectory: ctx.primaryPath)
                    .environmentObject(terminalSessionStore)
                    .frame(height: terminalHeight)
            }
        }
        .background(DesignSystem.Colors.backgroundDeep)
    }

    private func editorTopBar(ctx: EffectiveContext) -> some View {
        HStack(spacing: 8) {
            if let path = openFilesStore.openFilePath, !path.isEmpty {
                breadcrumb(path: path, ctx: ctx)
            } else {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Editor")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.2)) { showTerminal.toggle() }
            } label: {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(showTerminal ? Color.accentColor : Color.secondary.opacity(0.5))
                    .padding(4)
                    .background(
                        showTerminal ? Color.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle terminal")

            Button {
                withAnimation(.snappy(duration: 0.2)) { showBrowserPanel.toggle() }
            } label: {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(showBrowserPanel ? DesignSystem.Colors.browserColor : Color.secondary.opacity(0.5))
                    .padding(4)
                    .background(
                        showBrowserPanel ? DesignSystem.Colors.browserColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle browser")

            Button {
                withAnimation(.snappy(duration: 0.2)) { showChatPanel.toggle() }
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(showChatPanel ? Color.accentColor : Color.secondary.opacity(0.5))
                    .padding(4)
                    .background(
                        showChatPanel ? Color.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle chat panel")

            Button {
                gitPanelStore.isOpen.toggle()
            } label: {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(gitPanelStore.isOpen ? Color.accentColor : Color.secondary.opacity(0.5))
                    .padding(4)
                    .background(
                        gitPanelStore.isOpen ? Color.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle git panel")

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    chatPanelPosition = chatPanelPosition == "left" ? "right" : "left"
                }
            } label: {
                Image(systemName: chatPanelPosition == "left" ? "sidebar.left" : "sidebar.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help(chatPanelPosition == "left" ? "Move chat to right" : "Move chat to left")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(DesignSystem.Colors.backgroundPrimary.opacity(0.5))
    }

    private func breadcrumb(path: String, ctx: EffectiveContext) -> some View {
        let components = breadcrumbComponents(path: path, rootPaths: ctx.folderPaths)
        return HStack(spacing: 2) {
            ForEach(Array(components.enumerated()), id: \.offset) { idx, component in
                if idx > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.quaternary)
                }
                Text(component)
                    .font(.system(size: 11, weight: idx == components.count - 1 ? .medium : .regular))
                    .foregroundStyle(idx == components.count - 1 ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
    }

    private func breadcrumbComponents(path: String, rootPaths: [String]) -> [String] {
        for root in rootPaths {
            if path.hasPrefix(root + "/") {
                let relative = String(path.dropFirst(root.count + 1))
                let rootName = (root as NSString).lastPathComponent
                return [rootName] + relative.components(separatedBy: "/")
            }
        }
        return path.components(separatedBy: "/").suffix(3).map { String($0) }
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        ChatPanelView(
            selectedConversationId: $selectedConversationId,
            effectiveContext: effectiveContext(for: selectedConversationId, chatStore: chatStore, projectContextStore: projectContextStore),
            coderMode: $coderMode,
            showPlanPanel: $showPlanPanel,
            showDebugPanel: $showDebugPanel,
            showSwarmPanel: $showSwarmPanel,
            showCodeReviewPanel: $showCodeReviewPanel,
            showBrowserPanel: $showBrowserPanel,
            debugStore: debugStore
        )
        .environmentObject(providerRegistry)
        .environmentObject(chatStore)
        .environmentObject(projectContextStore)
        .environmentObject(openFilesStore)
        .environmentObject(planHistoryStore)
        .environmentObject(browserTabManager)
        .chatPanelContainer(
            style: ChatBackgroundStyle.from(raw: chatBackgroundStyle),
            cornerRadius: 14
        )
    }

    private func handleProjectFolderSelection(result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let paths = urls.map { $0.path(percentEncoded: false) }
        guard let contextId = projectContextStore.createOrReuseSingleProject(paths: paths) else { return }
        projectContextStore.activeContextId = contextId
        if workspaceStore.workspaces.contains(where: { $0.id == contextId }) {
            workspaceStore.activeWorkspaceId = contextId
        } else {
            workspaceStore.activeWorkspaceId = nil
        }
        workspaceStore.save()
        let ctx = projectContextStore.context(id: contextId)
        let folderScope = (ctx?.kind == .workspace) ? ctx?.activeFolderPath : nil
        if let lastId = projectContextStore.lastActiveConversationId(contextId: contextId, folderPath: folderScope),
           let lastConv = chatStore.conversation(for: lastId),
           lastConv.contextId == contextId,
           !lastConv.isArchived,
           lastConv.messages.contains(where: { $0.role == .user }) {
            selectedConversationId = lastId
        } else {
            selectedConversationId = chatStore.createConversation(contextId: contextId, contextFolderPath: folderScope)
        }
        let preferredProvider = chatStore.conversation(for: selectedConversationId)?.preferredProviderId
        providerRegistry.selectedProviderId = ProviderSupport.firstHealthyAgentProviderIdWithCodexFallback(
            preferred: preferredProvider,
            registry: providerRegistry
        )
    }
}
