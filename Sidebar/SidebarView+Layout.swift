import SwiftUI
import AppKit
import CoderEngine

extension SidebarView {
    private var sidebarTopContentInset: CGFloat { 24 }

    var sidebarContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    // Quick actions: inline flat rows
                    SidebarNewThreadButton(
                        onNewThread: { createThread(contextId: currentContext?.id) },
                        onOpenProject: { isSelectingProjectFolders = true }
                    )

                    // Search bar — inline, no box
                    SidebarSearchBar(query: $sidebarQuery)

                    // Context/Project section
                    contextSection
                        .padding(.top, DesignSystem.Spacing.sm)

                    // Threads list
                    threadsSection
                        .padding(.top, DesignSystem.Spacing.xs)

                    // Explorer (IDE mode only)
                    if isIDEMode, let context = currentContext, !context.folderPaths.isEmpty {
                        explorerSection(context: context)
                            .padding(.top, DesignSystem.Spacing.sm)
                    }
                }
                .padding(.top, sidebarTopContentInset)
                .padding(.horizontal, DesignSystem.Sidebar.insetMD)
                .padding(.bottom, DesignSystem.Sidebar.insetMD)
            }

            // Task cloud at bottom (fixed)
            taskCloudSection
                .padding(.horizontal, DesignSystem.Sidebar.insetMD)
                .padding(.vertical, DesignSystem.Spacing.sm)
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
