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
            minWidth: 180,
            maxWidth: 400,
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
            preferActiveContextForGlobalThread = false
            if let reusable = chatStore.reusableEmptyConversation(contextId: nil, contextFolderPath: nil) {
                selectedConversationId = reusable.id
            } else {
                selectedConversationId = chatStore.createConversation(
                    contextId: nil,
                    contextFolderPath: nil,
                    mode: nil
                )
            }
            return
        }
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
            } ?? chatStore.reusableEmptyConversation(
                contextId: defaultContextId,
                contextFolderPath: folderScope
            )
            selectedConversationId = reusableConversation?.id ?? chatStore.createConversation(
                contextId: defaultContextId,
                contextFolderPath: folderScope,
                mode: nil
            )
        }
    }

    func configureDefaultProviderSelection() {
        let preferred = chatStore.conversation(for: selectedConversationId)?.preferredProviderId
        if let resolved = ProviderSupport.preferredOrCurrentAgentProviderId(
            preferred: preferred,
            current: providerRegistry.selectedProviderId,
            registry: providerRegistry
        ) {
            providerRegistry.selectedProviderId = resolved
            return
        }
        if providerRegistry.selectedProviderId == nil {
            providerRegistry.selectedProviderId = ProviderSupport.firstHealthyAgentProviderId(
                preferred: nil,
                registry: providerRegistry
            )
        }
    }

    var editorArea: some View {
        editorAreaView
    }

    private var editorAreaView: some View {
        let ctx = effectiveContext(
            for: selectedConversationId,
            chatStore: chatStore,
            projectContextStore: projectContextStore,
            preferActiveContextForGlobalThread: preferActiveContextForGlobalThread
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

}
