import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoderEngine

extension ContentView {
    var configuredContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            configuredSidebar
        } detail: {
            configuredDetailContent
        }
            .onAppear(perform: configureInitialConversationSelection)
        .onAppear {
            configureDefaultProviderSelection()
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

    private var configuredSidebar: some View {
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
    }

    @ViewBuilder
    private var configuredDetailContent: some View {
        // #region agent log
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            if w < 100 || h < 100 {
                DebugSessionLog.log(
                    location: "ContentView+Layout:GeometryReader",
                    message: "detail geometry SUSPICIOUS",
                    data: ["width": Double(w), "height": Double(h), "coderMode": String(describing: coderMode)],
                    hypothesisId: "A"
                )
            }
            return configuredModeContent(detailWidth: w)
        }
        // #endregion
        .frame(minWidth: 720)
        .background(DesignSystem.Colors.backgroundDeep)
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder
    private func configuredModeContent(detailWidth: CGFloat) -> some View {
        switch coderMode {
        case .ide:
            ideModeContent(detailWidth: detailWidth)
        case .browser:
            browserModeContent(detailWidth: detailWidth)
        default:
            fallbackModeContent
        }
    }

    @ViewBuilder
    private func ideModeContent(detailWidth: CGFloat) -> some View {
        let chatIsLeft = chatPanelPosition == "left"
        let clampedChatW = min(CGFloat(chatPanelWidth), max(300, detailWidth * 0.45))
        let maxChatW = max(300, detailWidth * 0.45)
        // #region agent log
        let _ = detailWidth < 100 ? DebugSessionLog.log(
            location: "ContentView:ideModeContent",
            message: "ideMode detailWidth SUSPICIOUS",
            data: ["detailWidth": Double(detailWidth), "clampedChatW": Double(clampedChatW)],
            hypothesisId: "A"
        ) : ()
        // #endregion
        let clampedBrowserW = min(CGFloat(browserPanelWidth), max(300, detailWidth * 0.55))
        let maxBrowserW = max(300, detailWidth * 0.55)

        HStack(spacing: 0) {
            ActivityBarView(
                selectedItem: $activeActivityItem,
                showSettings: $showSettings
            )

            if showChatPanel && chatIsLeft {
                chatPanel
                    .frame(width: clampedChatW)
                chatPanelLeadingResizeHandle(clampedWidth: clampedChatW, maxWidth: maxChatW)
            }

            if let item = activeActivityItem, item != .settings {
                sidePanelContent(for: item)
                    .frame(width: max(180, min(CGFloat(sidePanelWidth), 400)))
                sidePanelResizeHandle
            }

            editorArea
                .layoutPriority(1)

            if showBrowserPanel {
                browserResizeHandle(clampedWidth: clampedBrowserW, maxWidth: maxBrowserW)
                BrowserPanelView(tabManager: browserTabManager)
                    .frame(width: clampedBrowserW)
            }

            if showChatPanel && !chatIsLeft {
                chatPanelTrailingResizeHandle(clampedWidth: clampedChatW, maxWidth: maxChatW)
                chatPanel
                    .frame(width: clampedChatW)
            }
        }
        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
    }

    @ViewBuilder
    private func browserModeContent(detailWidth: CGFloat) -> some View {
        let clampedBrowserW = min(CGFloat(browserPanelWidth), max(300, detailWidth * 0.65))
        let maxBrowserW = max(300, detailWidth * 0.65)

        HStack(spacing: 0) {
            chatPanel
                .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                .layoutPriority(1)

            if showBrowserPanel {
                browserResizeHandle(clampedWidth: clampedBrowserW, maxWidth: maxBrowserW, leading: true)
                BrowserPanelView(tabManager: browserTabManager)
                    .frame(width: clampedBrowserW)
            }
        }
        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
    }

    private var fallbackModeContent: some View {
        chatPanel
            .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
    }

    @ViewBuilder
    private func sidePanelContent(for item: ActivityBarItem) -> some View {
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
    }


}
