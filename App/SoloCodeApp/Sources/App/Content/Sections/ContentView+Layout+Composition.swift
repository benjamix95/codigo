import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoderEngine

extension ContentView {
    var workbenchTopInteractiveInset: CGFloat { 28 }

    @ViewBuilder
    private var detailBackground: some View {
        switch panelCoordinator.coderMode {
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
        if panelCoordinator.coderMode == .ide || panelCoordinator.coderMode == .browser {
            configuredDetailContent
        } else {
            HStack(spacing: 0) {
                if panelCoordinator.columnVisibility != .detailOnly {
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
            .animation(.snappy(duration: 0.2), value: panelCoordinator.columnVisibility)
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
        .fileImporter(
            isPresented: $panelCoordinator.showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: panelCoordinator.pendingFolderPickerKind == .openProject,
            onCompletion: handleUnifiedFolderSelection
        )
        .onChange(of: panelCoordinator.isSelectingProjectFolders) { newValue in
            guard newValue else { return }
            panelCoordinator.isSelectingProjectFolders = false
            panelCoordinator.pendingFolderPickerKind = .openProject
            panelCoordinator.showFolderPicker = true
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sidebarAddFolderToContext)) { notif in
            if let contextId = notif.userInfo?["contextId"] as? UUID {
                panelCoordinator.pendingFolderPickerKind = .addFolderToContext(contextId)
                panelCoordinator.showFolderPicker = true
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .sheet(isPresented: $panelCoordinator.showSettings) {
            SettingsView()
                .environmentObject(providerRegistry)
                .environmentObject(executionController)
                .environmentObject(providerUsageStore)
                .environmentObject(appUpdateCenter)
        }
        .onReceive(NotificationCenter.default.publisher(for: .coderOpenSettingsFromMenuBar)) { _ in
            panelCoordinator.showSettings = true
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .providersDidRegister)) { _ in
            syncThreadBoundProviderSelection(for: panelCoordinator.selectedConversationId)
        }
        .onReceive(appUpdateCenter.$availableUpdate.compactMap { $0 }) { update in
            panelCoordinator.pendingAppUpdate = update
            panelCoordinator.showAppUpdateAlert = true
        }
        // NOTE: isSelectingProjectFolders onChange is handled above via unified folder picker
        .onReceive(NotificationCenter.default.publisher(for: BrowserTabManager.browserShouldOpenNotification)) { _ in
            if !panelCoordinator.showBrowserPanel {
                withAnimation(.snappy(duration: 0.2)) { panelCoordinator.showBrowserPanel = true }
            }
        }
        .onChange(of: panelCoordinator.showPlanPanel) { isOpen in
            guard isOpen else { return }
            DispatchQueue.main.async {
                panelCoordinator.showDebugPanel = false; panelCoordinator.showSwarmPanel = false; panelCoordinator.showCodeReviewPanel = false
            }
        }
        .onChange(of: panelCoordinator.showDebugPanel) { isOpen in
            guard isOpen else { return }
            DispatchQueue.main.async {
                panelCoordinator.showPlanPanel = false; panelCoordinator.showSwarmPanel = false; panelCoordinator.showCodeReviewPanel = false
            }
        }
        .onChange(of: panelCoordinator.showSwarmPanel) { isOpen in
            guard isOpen else { return }
            DispatchQueue.main.async {
                panelCoordinator.showPlanPanel = false; panelCoordinator.showDebugPanel = false; panelCoordinator.showCodeReviewPanel = false
            }
        }
        .onChange(of: panelCoordinator.showCodeReviewPanel) { isOpen in
            guard isOpen else { return }
            DispatchQueue.main.async {
                panelCoordinator.showPlanPanel = false; panelCoordinator.showDebugPanel = false; panelCoordinator.showSwarmPanel = false
            }
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
        .onChange(of: panelCoordinator.coderMode) { newMode in
            withAnimation(.snappy(duration: 0.2)) {
                panelCoordinator.columnVisibility = (newMode == .ide || newMode == .browser) ? .detailOnly : .all
            }
            // Re-apply window style after mode change to strip any sidebar toggle
            // that SwiftUI re-adds when columnVisibility changes, and clear the title.
            // NOTE: Previously this applied the style 6 times (immediate + 5 delays
            // up to 2.0s). Each reapplication forces a full window redraw, causing
            // the UI to disappear temporarily. A single delayed application after
            // SwiftUI finishes its layout pass (0.3s) is sufficient.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                for window in NSApplication.shared.windows where window.canBecomeMain {
                    AppDelegate.applyMainWindowStyle(window)
                }
            }
        }
        .onChange(of: chatStore.conversations.map(\.id)) { conversationIds in
                guard !conversationIds.isEmpty else {
                    panelCoordinator.selectedConversationId = nil
                    return
                }
                if let selectedConversationId = panelCoordinator.selectedConversationId, conversationIds.contains(selectedConversationId) {
                    return
                }
                let defaultContextId: UUID?
                if panelCoordinator.preferActiveContextForGlobalThread {
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
                panelCoordinator.selectedConversationId = preferred ?? conversationIds.first
            }
        .onChange(of: projectContextStore.activeContextId) { newContextId in
            guard let newContextId else { return }
            let ctx = projectContextStore.context(id: newContextId)
            let folderScope = (ctx?.folderPaths.count ?? 0) > 1 ? ctx?.activeFolderPath : nil
            if let selectedId = panelCoordinator.selectedConversationId,
               let selected = chatStore.conversation(for: selectedId),
               !selected.isArchived,
               !chatStore.hasUserMessages(selected) {
                if selected.contextId != newContextId || selected.contextFolderPath != folderScope {
                    chatStore.setContext(conversationId: selectedId, contextId: newContextId)
                    chatStore.setContextFolder(conversationId: selectedId, folderPath: folderScope)
                }
                return
            }
            let conv = chatStore.conversation(for: panelCoordinator.selectedConversationId)
            guard conv?.contextId != newContextId else { return }
            if let lastId = projectContextStore.lastActiveConversationId(contextId: newContextId, folderPath: folderScope),
               let lastConv = chatStore.conversation(for: lastId),
               lastConv.contextId == newContextId,
               !lastConv.isArchived,
               chatStore.hasUserMessages(lastConv) {
                panelCoordinator.selectedConversationId = lastId
            } else if let reusable = chatStore.reusableEmptyConversation(contextId: newContextId, contextFolderPath: folderScope) {
                panelCoordinator.selectedConversationId = reusable.id
            } else {
                panelCoordinator.selectedConversationId = chatStore.createConversation(contextId: newContextId, contextFolderPath: folderScope)
            }
        }
        .alert(
            "Update Available",
            isPresented: $panelCoordinator.showAppUpdateAlert,
            presenting: panelCoordinator.pendingAppUpdate
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
                selectedConversationId: $panelCoordinator.selectedConversationId,
                showSettings: $panelCoordinator.showSettings,
                isSelectingProjectFolders: $panelCoordinator.isSelectingProjectFolders,
                preferActiveContextForGlobalThread: panelCoordinator.preferActiveContextForGlobalThread
            )
        }
        .environmentObject(providerRegistry)
        .environmentObject(chatStore)
        .environmentObject(workspaceStore)
        .environmentObject(projectContextStore)
        .environmentObject(openFilesStore)
        .environmentObject(toolTraceStore)
        .environmentObject(pipelineIntegrationService)
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
        switch panelCoordinator.coderMode {
        case .ide:
            ideModeContent(detailWidth: detailWidth)
        case .browser:
            browserModeContent(detailWidth: detailWidth)
        default:
            fallbackModeContent
        }
    }

}
