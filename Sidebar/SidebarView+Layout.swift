import SwiftUI
import AppKit
import CoderEngine

extension SidebarView {
    private var sidebarTopContentInset: CGFloat { 62 }

    var sidebarContent: some View {
        VStack(spacing: 0) {
            // Fixed header: Search + New Thread
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                SidebarSearchBar(query: $sidebarQuery)

                SidebarNewThreadButton(
                    onNewThread: { createThread(contextId: currentContext?.id) }
                )
            }
            .padding(.top, sidebarTopContentInset)
            .padding(.horizontal, DesignSystem.Sidebar.insetMD)
            .padding(.bottom, DesignSystem.Spacing.sm)

            // Scrollable threads (primary content)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    threadsSection
                }
                .padding(.horizontal, DesignSystem.Sidebar.insetMD)
                .padding(.bottom, DesignSystem.Sidebar.insetMD)
            }

            // Pinned context strip above footer
            contextStrip
                .padding(.horizontal, DesignSystem.Sidebar.insetMD)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .fileImporter(
            isPresented: $isSelectingAddFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleAddFolderSelection
        )
        .sheet(item: $contextToRename) { context in
            RenameContextSheet(context: context, onDismiss: { contextToRename = nil })
                .environmentObject(projectContextStore)
                .environmentObject(workspaceStore)
        }
        .sheet(item: $conversationToRename) { conv in
            RenameConversationSheet(conversation: conv, onDismiss: { conversationToRename = nil })
                .environmentObject(chatStore)
        }
        .onAppear {
            scheduleSidebarWorkspaceSync(currentContextId: currentContext?.id)
        }
        .onChange(of: currentContextSyncFingerprint) { _ in
            scheduleSidebarWorkspaceSync(currentContextId: currentContext?.id)
        }
    }
}
