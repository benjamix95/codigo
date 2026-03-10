import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoderEngine

extension ContentView {
    var workbenchTopInteractiveInset: CGFloat { 28 }

    @ViewBuilder
    private var detailBackground: some View {
        switch coderMode {
        case .ide, .browser:
            ideBackdrop
        default:
            DesignSystem.Colors.backgroundDeep
        }
    }

    var activeContextSyncFingerprint: String {
        guard let context = projectContextStore.activeContext else { return "none" }
        let folders = context.folderPaths.joined(separator: "|")
        let exclusions = context.excludedPaths.joined(separator: "|")
        let activeRoot = context.activeFolderPath ?? ""
        return "\(context.id.uuidString)#\(folders)#\(exclusions)#\(activeRoot)"
    }

    /// We always use a custom HStack layout instead of NavigationSplitView so
    /// macOS never injects native sidebar chrome (divider, toggle button,
    /// separate titlebar treatment). The traffic lights sit visually inside
    /// the custom sidebar.
    @ViewBuilder
    private var contentRoot: some View {
        if coderMode == .ide || coderMode == .browser {
            configuredDetailContent
        } else {
            HStack(spacing: 0) {
                if columnVisibility != .detailOnly {
                    configuredSidebar
                        .frame(width: 260)
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    // Subtle divider between sidebar and content
                    Rectangle()
                        .fill(DesignSystem.Colors.borderSubtle)
                        .frame(width: 1)
                        .padding(.vertical, 14)
                }

                configuredDetailContent
                    .frame(maxWidth: .infinity)
            }
            .animation(.snappy(duration: 0.2), value: columnVisibility)
        }
    }

    var configuredContent: some View {
        contentRoot
        .onAppear(perform: configureInitialConversationSelection)
        .onAppear {
            configureDefaultProviderSelection()
        }
        .onAppear {
            workspaceStore.syncActiveWorkspace(with: projectContextStore.activeContext)
        }
        .onChange(of: activeContextSyncFingerprint) { _ in
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
        .onChange(of: isSelectingProjectFolders) { isPresented in
            if isPresented { NSApp.activate(ignoringOtherApps: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: BrowserTabManager.browserShouldOpenNotification)) { _ in
            if !showBrowserPanel {
                withAnimation(.snappy(duration: 0.2)) { showBrowserPanel = true }
            }
        }
        .onChange(of: showPlanPanel) { isOpen in
            guard isOpen else { return }
            showDebugPanel = false; showSwarmPanel = false; showCodeReviewPanel = false
        }
        .onChange(of: showDebugPanel) { isOpen in
            guard isOpen else { return }
            showPlanPanel = false; showSwarmPanel = false; showCodeReviewPanel = false
        }
        .onChange(of: showSwarmPanel) { isOpen in
            guard isOpen else { return }
            showPlanPanel = false; showDebugPanel = false; showCodeReviewPanel = false
        }
        .onChange(of: showCodeReviewPanel) { isOpen in
            guard isOpen else { return }
            showPlanPanel = false; showDebugPanel = false; showSwarmPanel = false
        }
        .onChangeCompat(of: gitPanelStore.isOpen) { wasOpen, isOpen in
            guard autoResizeSidePanels else { return }
            let panelWidth = CGFloat(gitPanelWidth) + 12
            if isOpen && !wasOpen {
                WindowResizeHelper.adjustWidth(by: panelWidth, animate: false)
            } else if !isOpen && wasOpen {
                WindowResizeHelper.adjustWidth(by: -panelWidth, animate: false)
            }
        }
        .onChange(of: coderMode) { newMode in
            withAnimation(.snappy(duration: 0.2)) {
                columnVisibility = (newMode == .ide || newMode == .browser) ? .detailOnly : .all
            }
            // Re-apply window style after mode change to strip any sidebar toggle
            // that SwiftUI re-adds when columnVisibility changes, and clear the title.
            DispatchQueue.main.async {
                for window in NSApplication.shared.windows where window.canBecomeMain {
                    AppDelegate.applyMainWindowStyle(window)
                }
            }
            for extraDelay in [0.3, 0.6, 1.0, 1.5, 2.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + extraDelay) {
                    for window in NSApplication.shared.windows where window.canBecomeMain {
                        AppDelegate.applyMainWindowStyle(window)
                    }
                }
            }
        }
        .onChange(of: chatStore.conversations.map(\.id)) { conversationIds in
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
        .onChange(of: projectContextStore.activeContextId) { newContextId in
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
        ZStack {
            DesignSystem.Colors.backgroundSecondary
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)
            SidebarView(
                selectedConversationId: $selectedConversationId,
                showSettings: $showSettings,
                isSelectingProjectFolders: $isSelectingProjectFolders,
                preferActiveContextForGlobalThread: preferActiveContextForGlobalThread
            )
        }
        .environmentObject(providerRegistry)
        .environmentObject(chatStore)
        .environmentObject(workspaceStore)
        .environmentObject(projectContextStore)
        .environmentObject(openFilesStore)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }

    @ViewBuilder
    private var configuredDetailContent: some View {
        GeometryReader { geo in
            configuredModeContent(detailWidth: geo.size.width)
        }
        .frame(minWidth: 720)
        .background(detailBackground)
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

}
