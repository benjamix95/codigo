import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoderEngine

extension ContentView {
    @ViewBuilder
    func chatPanelLeadingResizeHandle(clampedWidth: CGFloat, maxWidth: CGFloat) -> some View {
        PanelResizeHandle(
            panelWidth: Binding(
                get: { clampedWidth },
                set: { chatPanelWidth = Double($0) }
            ),
            minWidth: 300,
            maxWidth: maxWidth,
            leadingEdge: false
        )
    }

    @ViewBuilder
    func chatPanelTrailingResizeHandle(clampedWidth: CGFloat, maxWidth: CGFloat) -> some View {
        PanelResizeHandle(
            panelWidth: Binding(
                get: { clampedWidth },
                set: { chatPanelWidth = Double($0) }
            ),
            minWidth: 300,
            maxWidth: maxWidth,
            leadingEdge: true
        )
    }

    @ViewBuilder
    var sidePanelResizeHandle: some View {
        PanelResizeHandle(
            panelWidth: Binding(
                get: { CGFloat(sidePanelWidth) },
                set: { sidePanelWidth = Double($0) }
            ),
            minWidth: 240,
            maxWidth: 380,
            leadingEdge: false
        )
    }

    @ViewBuilder
    func browserResizeHandle(
        clampedWidth: CGFloat,
        maxWidth: CGFloat,
        leading: Bool = true
    ) -> some View {
        PanelResizeHandle(
            panelWidth: Binding(
                get: { clampedWidth },
                set: { browserPanelWidth = Double($0) }
            ),
            minWidth: 300,
            maxWidth: maxWidth,
            leadingEdge: leading
        )
    }

    func configureInitialConversationSelection() {
        projectContextStore.ensureWorkspaceContexts(workspaceStore.workspaces)
        if WindowLaunchIntentStore.shared.consumeCleanWindowIntent() {
            panelCoordinator.preferActiveContextForGlobalThread = false
            if let reusable = chatStore.reusableEmptyConversation(contextId: nil, contextFolderPath: nil) {
                panelCoordinator.selectedConversationId = reusable.id
            } else {
                panelCoordinator.selectedConversationId = chatStore.createConversation(
                    contextId: nil,
                    contextFolderPath: nil,
                    mode: nil
                )
            }
            return
        }
        guard panelCoordinator.selectedConversationId == nil else { return }
        let defaultContextId = projectContextStore.activeContextId
        let ctx = projectContextStore.context(id: defaultContextId)
        let folderScope = (ctx?.folderPaths.count ?? 0) > 1 ? ctx?.activeFolderPath : nil
        if let contextId = defaultContextId,
           let lastId = projectContextStore.lastActiveConversationId(contextId: contextId, folderPath: folderScope),
           let lastConv = chatStore.conversation(for: lastId),
           lastConv.contextId == contextId,
           !lastConv.isArchived {
            panelCoordinator.selectedConversationId = lastId
        } else {
            let reusableConversation = chatStore.conversations.first { conv in
                !conv.isArchived
                    && conv.contextId == defaultContextId
                    && conv.contextFolderPath == folderScope
                    && (conv.mode == nil || conv.mode == .agent)
            } ?? chatStore.reusableEmptyConversation(
                contextId: defaultContextId,
                contextFolderPath: folderScope
            )
            panelCoordinator.selectedConversationId = reusableConversation?.id ?? chatStore.createConversation(
                contextId: defaultContextId,
                contextFolderPath: folderScope,
                mode: nil
            )
        }
    }

    func configureDefaultProviderSelection() {
        syncThreadBoundProviderSelection(for: panelCoordinator.selectedConversationId)
    }

    var editorArea: some View {
        editorAreaView
    }

    private var editorAreaView: some View {
        let ctx = effectiveContext(
            for: panelCoordinator.selectedConversationId,
            chatStore: chatStore,
            projectContextStore: projectContextStore,
            preferActiveContextForGlobalThread: panelCoordinator.preferActiveContextForGlobalThread
        )

        return VStack(spacing: 10) {
            editorTopBar(ctx: ctx)

            EditorPlaceholderView(folderPaths: ctx.folderPaths)
                .environmentObject(openFilesStore)
                .environmentObject(editorSplitStore)
                .environmentObject(editorPanelsStore)
                .environmentObject(editorQuickOpenStore)
                .environmentObject(editorDiagnosticsStore)
                .environmentObject(editorSymbolsStore)
                .environmentObject(editorCommandDispatchStore)
                .environmentObject(editorNavigationDispatchStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(DesignSystem.Colors.backgroundDeep.opacity(0.94))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            if panelCoordinator.showTerminal {
                TerminalPanelView(workingDirectory: ctx.primaryPath)
                    .environmentObject(terminalSessionStore)
                    .frame(height: panelCoordinator.terminalHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(DesignSystem.Colors.backgroundPrimary.opacity(0.86))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(10)
        .background(Color.clear)
    }

}
