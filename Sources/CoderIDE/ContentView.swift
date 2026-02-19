import SwiftUI
import AppKit
import CoderEngine

enum ContentTab: String, CaseIterable {
    case editor = "Editor"
    case terminal = "Terminale"

    var icon: String {
        switch self {
        case .editor: return "doc.text.fill"
        case .terminal: return "terminal.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @State private var selectedConversationId: UUID?
    @State private var contentTab: ContentTab = .editor
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedConversationId: $selectedConversationId)
                .environmentObject(chatStore)
                .environmentObject(workspaceStore)
                .environmentObject(openFilesStore)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            HSplitView {
                if showEditorPanel {
                    editorPanel
                        .frame(minWidth: 350, idealWidth: 450)
                }

                ChatPanelView(
                    conversationId: selectedConversationId,
                    effectiveContext: effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore)
                )
                .environmentObject(providerRegistry)
                .environmentObject(chatStore)
                .environmentObject(openFilesStore)
                .frame(minWidth: 380, idealWidth: 500)
            }
        }
        .onAppear {
            if providerRegistry.selectedProviderId == nil {
                providerRegistry.selectedProviderId = "codex-cli"
            }
            if selectedConversationId == nil, let first = chatStore.conversations.first {
                selectedConversationId = first.id
            }
        }
    }

    private var isIDEMode: Bool { providerRegistry.selectedProviderId == "openai-api" }

    private var showEditorPanel: Bool {
        isIDEMode || effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore).hasContext
    }

    // MARK: - Editor Panel
    private var editorPanel: some View {
        VStack(spacing: 0) {
            editorTabBar
            Divider()
            Group {
                let ctx = effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore)
                switch contentTab {
                case .editor:
                    EditorPlaceholderView(folderPaths: ctx.folderPaths, openFilePath: openFilesStore.openFilePath)
                case .terminal:
                    TerminalPanelView(workingDirectory: ctx.primaryPath)
                }
            }
        }
    }

    private var editorTabBar: some View {
        HStack(spacing: 2) {
            ForEach(ContentTab.allCases, id: \.self) { tab in
                editorTabButton(for: tab)
            }
            Spacer()
            contextIndicatorView
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var contextIndicatorView: some View {
        let ctx = effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore)
        if ctx.hasContext {
            HStack(spacing: 4) {
                Image(systemName: ctx.isWorkspace ? "folder.fill" : "folder")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(ctx.displayLabel)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.06), in: Capsule())
        }
    }

    private func editorTabButton(for tab: ContentTab) -> some View {
        let selected = contentTab == tab
        return Button { contentTab = tab } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 10))
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: selected ? .medium : .regular))
            }
            .foregroundStyle(selected ? Color.accentColor : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                selected ? Color.accentColor.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .hoverHighlight(Color.accentColor.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
