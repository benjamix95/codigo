import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoderEngine

extension ContentView {
    var activeContextSyncFingerprint: String {
        guard let context = projectContextStore.activeContext else { return "none" }
        let folders = context.folderPaths.joined(separator: "|")
        let exclusions = context.excludedPaths.joined(separator: "|")
        let activeRoot = context.activeFolderPath ?? ""
        return "\(context.id.uuidString)#\(folders)#\(exclusions)#\(activeRoot)"
    }

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
        .onAppear {
            workspaceStore.syncActiveWorkspace(with: projectContextStore.activeContext)
        }
        .onChange(of: activeContextSyncFingerprint) { _, _ in
            workspaceStore.syncActiveWorkspace(with: projectContextStore.activeContext)
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
            syncThreadBoundProviderSelection(for: selectedConversationId)
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
                let defaultContextId: UUID?
                if preferActiveContextForGlobalThread {
                    defaultContextId = projectContextStore.activeContextId
                } else {
                    defaultContextId = nil
                }
                let ctx = projectContextStore.context(id: defaultContextId)
                let folderScope = (ctx?.folderPaths.count ?? 0) > 1 ? ctx?.activeFolderPath : nil
                let preferred = chatStore.conversations.first { conv in
                    !conv.isArchived
                        && conv.contextId == defaultContextId
                        && conv.contextFolderPath == folderScope
                }?.id
                selectedConversationId = preferred ?? conversationIds.first
            }
        .onChange(of: projectContextStore.activeContextId) { _, newContextId in
            guard let newContextId else { return }
            let ctx = projectContextStore.context(id: newContextId)
            let folderScope = (ctx?.folderPaths.count ?? 0) > 1 ? ctx?.activeFolderPath : nil
            if let selectedId = selectedConversationId,
               let selected = chatStore.conversation(for: selectedId),
               !selected.isArchived,
               !chatStore.hasUserMessages(selected) {
                if selected.contextId != newContextId || selected.contextFolderPath != folderScope {
                    chatStore.setContext(conversationId: selectedId, contextId: newContextId)
                    chatStore.setContextFolder(conversationId: selectedId, folderPath: folderScope)
                }
                return
            }
            let conv = chatStore.conversation(for: selectedConversationId)
            guard conv?.contextId != newContextId else { return }
            if let lastId = projectContextStore.lastActiveConversationId(contextId: newContextId, folderPath: folderScope),
               let lastConv = chatStore.conversation(for: lastId),
               lastConv.contextId == newContextId,
               !lastConv.isArchived,
               chatStore.hasUserMessages(lastConv) {
                selectedConversationId = lastId
            } else if let reusable = chatStore.reusableEmptyConversation(contextId: newContextId, contextFolderPath: folderScope) {
                selectedConversationId = reusable.id
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
            isSelectingProjectFolders: $isSelectingProjectFolders,
            preferActiveContextForGlobalThread: preferActiveContextForGlobalThread
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
        GeometryReader { geo in
            configuredModeContent(detailWidth: geo.size.width)
        }
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
        let ctx = effectiveContext(
            for: selectedConversationId,
            chatStore: chatStore,
            projectContextStore: projectContextStore,
            preferActiveContextForGlobalThread: preferActiveContextForGlobalThread
        )
        let chatIsLeft = chatPanelPosition == "left"
        let clampedChatW = ContentPanelWidthPolicy.clampedWidth(
            storedWidth: chatPanelWidth,
            detailWidth: detailWidth,
            fraction: 0.45
        )
        let maxChatW = ContentPanelWidthPolicy.maxWidth(detailWidth: detailWidth, fraction: 0.45)
        let clampedBrowserW = ContentPanelWidthPolicy.clampedWidth(
            storedWidth: browserPanelWidth,
            detailWidth: detailWidth,
            fraction: 0.55
        )
        let maxBrowserW = ContentPanelWidthPolicy.maxWidth(detailWidth: detailWidth, fraction: 0.55)
        let clampedSidePanelW = max(220, min(CGFloat(sidePanelWidth), 320))

        ZStack {
            ideBackdrop

            HStack(spacing: 10) {
                if showChatPanel && chatIsLeft {
                    ideSurface(tint: DesignSystem.Colors.agentColor) {
                        chatPanel
                            .frame(width: clampedChatW)
                    }
                    chatPanelLeadingResizeHandle(clampedWidth: clampedChatW, maxWidth: maxChatW)
                }

                ideWorkbenchColumn(ctx: ctx, sidePanelWidth: clampedSidePanelW)

                if activeActivityItem != nil && activeActivityItem != .settings {
                    sidePanelResizeHandle
                }

                ideSurface(tint: DesignSystem.Colors.info) {
                    editorArea
                        .layoutPriority(1)
                }

                if showBrowserPanel {
                    browserResizeHandle(clampedWidth: clampedBrowserW, maxWidth: maxBrowserW)
                    ideSurface(tint: DesignSystem.Colors.browserColor) {
                        BrowserPanelView(tabManager: browserTabManager)
                            .frame(width: clampedBrowserW)
                    }
                }

                if showChatPanel && !chatIsLeft {
                    chatPanelTrailingResizeHandle(clampedWidth: clampedChatW, maxWidth: maxChatW)
                    ideSurface(tint: DesignSystem.Colors.agentColor) {
                        chatPanel
                            .frame(width: clampedChatW)
                    }
                }
            }
            .padding(10)
        }
        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
    }

    @ViewBuilder
    private func browserModeContent(detailWidth: CGFloat) -> some View {
        let clampedBrowserW = ContentPanelWidthPolicy.clampedWidth(
            storedWidth: browserPanelWidth,
            detailWidth: detailWidth,
            fraction: 0.65
        )
        let maxBrowserW = ContentPanelWidthPolicy.maxWidth(detailWidth: detailWidth, fraction: 0.65)

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

}
