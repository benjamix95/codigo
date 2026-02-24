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
    @StateObject private var debugStore = DebugStore()
    @State private var selectedConversationId: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showTerminal = false
    @State private var terminalHeight: CGFloat = 200
    @State private var showSettings = false
    @State private var showPlanPanel = false
    @State private var showDebugPanel = false
    @State private var isSelectingProjectFolders = false
    @AppStorage("chat_background_style") private var chatBackgroundStyle = ChatBackgroundStyle.defaultRawValue

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedConversationId: $selectedConversationId, showSettings: $showSettings, isSelectingProjectFolders: $isSelectingProjectFolders)
                .environmentObject(providerRegistry)
                .environmentObject(chatStore)
                .environmentObject(workspaceStore)
                .environmentObject(projectContextStore)
                .environmentObject(openFilesStore)
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        } detail: {
            HStack(spacing: 6) {
                if showEditorPanel {
                    idePanel
                        .frame(minWidth: 350, idealWidth: 450)
                }
                chatPanel
                    .frame(minWidth: 380, idealWidth: 500)
                if gitPanelStore.isOpen {
                    GitPanelView(
                        store: gitPanelStore,
                        effectiveContext: effectiveContext(for: selectedConversationId, chatStore: chatStore, projectContextStore: projectContextStore),
                        onOpenFile: { openFilesStore.openFile($0) }
                    )
                    .environmentObject(providerRegistry)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(DesignSystem.Colors.backgroundDeep)
            .ignoresSafeArea(.container, edges: .top)
        }
        .onAppear {
            // Initialize selection ONLY on first launch, otherwise onAppear would overwrite
            // the conversation chosen by the user (e.g. after "New thread") every time the view reappears.
            guard selectedConversationId == nil else {
                return
            }
            // Prefer projectContextStore: it is the last context actually used.
            let defaultContextId = projectContextStore.activeContextId ?? workspaceStore.activeWorkspaceId
            let ctx = projectContextStore.context(id: defaultContextId)
            let folderScope = (ctx?.kind == .workspace) ? ctx?.activeFolderPath : nil
            // One thread per context: use lastActive or reuse an existing thread, creating
            // a new thread only when no candidate exists.
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
            if let preferred = agentConv?.preferredProviderId,
               ProviderSupport.isAgentCompatibleProvider(id: preferred),
               providerRegistry.provider(for: preferred) != nil {
                providerRegistry.selectedProviderId = preferred
            } else {
                providerRegistry.selectedProviderId = "codex-cli"
            }
        }
        .fileImporter(isPresented: $isSelectingProjectFolders, allowedContentTypes: [.folder], allowsMultipleSelection: true, onCompletion: handleProjectFolderSelection)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(providerRegistry)
                .environmentObject(executionController)
                .environmentObject(providerUsageStore)
        }
        .onReceive(NotificationCenter.default.publisher(for: .coderOpenSettingsFromMenuBar)) { _ in
            showSettings = true
            NSApp.activate(ignoringOtherApps: true)
        }
        .onChange(of: isSelectingProjectFolders) { _, isPresented in
            if isPresented { NSApp.activate(ignoringOtherApps: true) }
        }
        .onChange(of: projectContextStore.activeContextId) { _, newContextId in
            guard let newContextId else { return }
            if let selectedId = selectedConversationId,
                let selected = chatStore.conversation(for: selectedId),
                !selected.isArchived,
                selected.messages.isEmpty
            {
                // If the user just manually created an empty thread, do not overwrite the selection.
                return
            }
            let conv = chatStore.conversation(for: selectedConversationId)
            guard conv?.contextId != newContextId else { return }
            let ctx = projectContextStore.context(id: newContextId)
            let folderScope = (ctx?.kind == .workspace) ? ctx?.activeFolderPath : nil
            // If there's a thread you worked on in this tab, show it; otherwise new thread
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
    }

    private var showEditorPanel: Bool {
        let conv = chatStore.conversation(for: selectedConversationId)
        if conv?.mode == .ide { return true }
        let pid = providerRegistry.selectedProviderId
        return ProviderSupport.isIDEProvider(id: pid) && !ProviderSupport.isAgentCompatibleProvider(id: pid)
    }

    // MARK: - IDE Panel
    private var idePanel: some View {
        VStack(spacing: 0) {
            // Align the editor bar to the same interactive level as the chat panel.
            Color.clear
                .frame(height: 22)
                .allowsHitTesting(false)
            ideHeader
            Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.4)).frame(height: 0.5)

            let ctx = effectiveContext(for: selectedConversationId, chatStore: chatStore, projectContextStore: projectContextStore)
            EditorPlaceholderView(folderPaths: ctx.folderPaths)
                .environmentObject(openFilesStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showTerminal {
                Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.4)).frame(height: 0.5)
                TerminalPanelView(workingDirectory: ctx.primaryPath)
                    .frame(height: terminalHeight)
            }
        }
        .sidebarPanel(cornerRadius: 14)
    }

    private var ideHeader: some View {
        HStack(spacing: 8) {
            if let path = openFilesStore.openFilePath, !path.isEmpty {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Editor")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            contextBadge

            Button { withAnimation(.easeOut(duration: 0.2)) { showTerminal.toggle() } } label: {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(showTerminal ? DesignSystem.Colors.agentColor : Color(nsColor: .tertiaryLabelColor))
                    .padding(4)
                    .background(showTerminal ? DesignSystem.Colors.agentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Show/hide terminal")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var contextBadge: some View {
        let ctx = effectiveContext(for: selectedConversationId, chatStore: chatStore, projectContextStore: projectContextStore)
        if ctx.hasContext {
            HStack(spacing: 4) {
                Image(systemName: ctx.isWorkspace ? "folder.fill" : "folder")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                Text(ctx.displayLabel)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.12), lineWidth: 0.5))
        }
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
    }

    // MARK: - Chat Panel
    private var chatPanel: some View {
        ChatPanelView(
            selectedConversationId: $selectedConversationId,
            effectiveContext: effectiveContext(for: selectedConversationId, chatStore: chatStore, projectContextStore: projectContextStore),
            showPlanPanel: $showPlanPanel,
            showDebugPanel: $showDebugPanel,
            debugStore: debugStore
        )
        .environmentObject(providerRegistry)
        .environmentObject(chatStore)
        .environmentObject(projectContextStore)
        .environmentObject(openFilesStore)
        .environmentObject(planHistoryStore)
        .chatPanelContainer(
            style: ChatBackgroundStyle.from(raw: chatBackgroundStyle),
            cornerRadius: 14
        )
    }
}
