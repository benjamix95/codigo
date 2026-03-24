import SwiftUI
import CoderEngine

extension SidebarView {
    /// Top content inset to clear the traffic-light area.
    private var sidebarTopContentInset: CGFloat { 62 }

    var sidebarContent: some View {
        VStack(spacing: 0) {
            // Fixed header: Search + New Thread + Skills + Rules
            VStack(alignment: .leading, spacing: 6) {
                SidebarSearchBar(query: $query)
                SidebarNewThreadButton(onNewThread: { createThread(contextId: activeContext?.id) })
                SidebarSkillsButton(showSkillsSheet: $showSkillsSheet)
                SidebarRulesButton(showRulesSheet: $showRulesSheet)
            }
            .padding(.top, sidebarTopContentInset)
            .padding(.horizontal, DesignSystem.Sidebar.insetMD)
            .padding(.bottom, 12)

            // Scrollable thread list (primary content)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    threadsSection
                }
                .padding(.horizontal, DesignSystem.Sidebar.insetMD)
                .padding(.bottom, DesignSystem.Sidebar.insetMD)
            }

            // Pinned context strip above footer
            contextStrip
                .padding(.horizontal, DesignSystem.Sidebar.insetMD)

            footer
        }
        .sheet(isPresented: $showSkillsSheet) {
            ProjectSkillsSheet(projectRoot: activeContext?.activeFolderPath)
        }
        .sheet(isPresented: $showRulesSheet) {
            SidebarRulesSheet(projectRoot: activeContext?.activeFolderPath)
        }
        .sheet(item: $contextToRename) { context in
            RenameContextSheet(context: context, onDismiss: { contextToRename = nil })
                .environmentObject(projectContextStore)
                .environmentObject(workspaceStore)
        }
        .sheet(item: $conversationToRename) { conv in
            RenameConversationSheet(conversation: conv, onDismiss: { conversationToRename = nil })
                .environmentObject(chatStore)
        }
    }
}
