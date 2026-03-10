import SwiftUI
import AppKit
import CoderEngine

extension SidebarView {
    private var sidebarTopContentInset: CGFloat { 60 }

    var sidebarContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    SidebarNewThreadButton(
                        onNewThread: { createThread(contextId: currentContext?.id) },
                        onOpenProject: { isSelectingProjectFolders = true }
                    )

                    SidebarSearchBar(query: $sidebarQuery)

                    contextSection
                        .padding(.top, DesignSystem.Spacing.sm)

                    threadsSection
                        .padding(.top, DesignSystem.Spacing.xs)

                    if isIDEMode, let context = currentContext, !context.folderPaths.isEmpty {
                        explorerSection(context: context)
                            .padding(.top, DesignSystem.Spacing.sm)
                    }
                }
                .padding(.top, sidebarTopContentInset)
                .padding(.horizontal, DesignSystem.Sidebar.insetMD)
                .padding(.bottom, DesignSystem.Sidebar.insetMD)
            }

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
