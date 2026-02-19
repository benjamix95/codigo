import SwiftUI
import AppKit
import CoderEngine

struct ContentView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @EnvironmentObject var executionController: ExecutionController
    @State private var selectedConversationId: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showTerminal = false
    @State private var terminalHeight: CGFloat = 200
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedConversationId: $selectedConversationId, showSettings: $showSettings)
                .environmentObject(chatStore)
                .environmentObject(workspaceStore)
                .environmentObject(openFilesStore)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            HStack(spacing: 6) {
                if showEditorPanel {
                    idePanel
                        .frame(minWidth: 350, idealWidth: 450)
                }
                chatPanel
                    .frame(minWidth: 380, idealWidth: 500)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(DesignSystem.Colors.backgroundDeep)
            .ignoresSafeArea(.container, edges: .top)
        }
        .onAppear {
            if providerRegistry.selectedProviderId == nil { providerRegistry.selectedProviderId = "codex-cli" }
            if selectedConversationId == nil, let first = chatStore.conversations.first { selectedConversationId = first.id }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(providerRegistry)
                .environmentObject(executionController)
        }
    }

    private var showEditorPanel: Bool {
        ProviderSupport.isIDEProvider(id: providerRegistry.selectedProviderId)
    }

    // MARK: - IDE Panel
    private var idePanel: some View {
        VStack(spacing: 0) {
            ideHeader
            Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.4)).frame(height: 0.5)

            let ctx = effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore)
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
            .help("Mostra/nascondi terminale")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var contextBadge: some View {
        let ctx = effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore)
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

    // MARK: - Chat Panel
    private var chatPanel: some View {
        ChatPanelView(
            selectedConversationId: $selectedConversationId,
            effectiveContext: effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore)
        )
        .environmentObject(providerRegistry)
        .environmentObject(chatStore)
        .environmentObject(openFilesStore)
        .sidebarPanel(cornerRadius: 14)
    }
}
