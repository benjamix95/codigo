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
    @State private var sidebarCollapsed = false
    
    var body: some View {
        ZStack {
            // Animated background
            AnimatedGradientBackground()
            
            // Floating orbs for depth
            FloatingOrb(color: DesignSystem.Colors.primary, size: 300)
                .offset(x: -100, y: -100)
            FloatingOrb(color: DesignSystem.Colors.ideColor, size: 250)
                .offset(x: 200, y: 150)
            FloatingOrb(color: DesignSystem.Colors.agentColor, size: 200)
                .offset(x: -50, y: 200)
            
            // Main content with separate glass panels
            HStack(spacing: DesignSystem.Spacing.md) {
                // Sidebar Panel (separate glass box)
                if !sidebarCollapsed {
                    SidebarView(selectedConversationId: $selectedConversationId)
                        .environmentObject(chatStore)
                        .environmentObject(workspaceStore)
                        .environmentObject(openFilesStore)
                        .frame(width: 260)
                        .liquidGlass(cornerRadius: DesignSystem.CornerRadius.xl, borderOpacity: 0.1)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                
                // Center Panel - Editor/Terminal (in IDE mode or when workspace active)
                if showEditorPanel {
                    editorPanel
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                
                // Chat Panel (separate glass box) - expands when editor hidden
                ChatPanelView(
                    conversationId: selectedConversationId,
                    effectiveContext: effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore)
                )
                .environmentObject(providerRegistry)
                .environmentObject(chatStore)
                .environmentObject(openFilesStore)
                .frame(
                    minWidth: showEditorPanel ? 380 : 500,
                    idealWidth: showEditorPanel ? 420 : .infinity,
                    maxWidth: showEditorPanel ? 500 : .infinity
                )
                .liquidGlass(cornerRadius: DesignSystem.CornerRadius.xl, borderOpacity: 0.1)
            }
            .padding(DesignSystem.Spacing.lg)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showEditorPanel)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        sidebarCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.body.weight(.medium))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            // Set default provider to Codex CLI (Agent mode)
            if providerRegistry.selectedProviderId == nil {
                providerRegistry.selectedProviderId = "codex-cli"
            }
            // Seleziona automaticamente la prima conversazione se nessuna è selezionata
            if selectedConversationId == nil, let first = chatStore.conversations.first {
                selectedConversationId = first.id
            }
        }
    }
    
    // MARK: - IDE Mode Check
    private var isIDEMode: Bool {
        providerRegistry.selectedProviderId == "openai-api"
    }
    
    /// Pannello editor visibile: in IDE mode o quando c'è contesto (workspace o ad-hoc)
    private var showEditorPanel: Bool {
        isIDEMode || effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore).hasContext
    }
    
    // MARK: - Editor Panel (separate glass box)
    private var editorPanel: some View {
        VStack(spacing: 0) {
            // Tab Bar
            glassTabBar
            
            // Content
            Group {
                let ctx = effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore)
                switch contentTab {
                case .editor:
                    EditorPlaceholderView(
                        folderPaths: ctx.folderPaths,
                        openFilePath: openFilesStore.openFilePath
                    )
                case .terminal:
                    TerminalPanelView(workingDirectory: ctx.primaryPath)
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 500, maxWidth: 600)
        .liquidGlass(cornerRadius: DesignSystem.CornerRadius.xl, borderOpacity: 0.1)
    }
    
    private var glassTabBar: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            ForEach(ContentTab.allCases, id: \.self) { tab in
                glassTabButton(for: tab)
            }
            
            Spacer()
            
            // Context indicator
            contextIndicatorView
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background {
            Rectangle()
                .fill(Color.white.opacity(0.02))
        }
        .overlay {
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(DesignSystem.Colors.divider)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
    
    @ViewBuilder
    private var contextIndicatorView: some View {
        let ctx = effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore)
        if ctx.hasContext {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: ctx.isWorkspace ? "folder.fill" : "folder")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.primary)
                Text(ctx.displayLabel)
                    .font(DesignSystem.Typography.captionMedium)
                    .lineLimit(1)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .liquidGlass(
                cornerRadius: DesignSystem.CornerRadius.medium,
                tint: DesignSystem.Colors.primary
            )
        }
    }
    
    private func glassTabButton(for tab: ContentTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                contentTab = tab
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: tab.icon)
                    .font(DesignSystem.Typography.subheadline)
                Text(tab.rawValue)
                    .font(DesignSystem.Typography.subheadlineMedium)
            }
            .foregroundStyle(contentTab == tab ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textTertiary)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background {
                if contentTab == tab {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(DesignSystem.Colors.primary.opacity(0.15))
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 0.5)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(scale: 1.01)
    }
}
