import Foundation

@MainActor
protocol WorktreeConversationRouting {
    func switchConversation(
        conversationId: UUID?,
        toProjectPath projectPath: String,
        chatStore: ChatStore,
        projectContextStore: ProjectContextStore,
        workspaceStore: WorkspaceStore
    ) throws
}

struct DefaultWorktreeConversationRouter: WorktreeConversationRouting {
    func switchConversation(
        conversationId: UUID?,
        toProjectPath projectPath: String,
        chatStore: ChatStore,
        projectContextStore: ProjectContextStore,
        workspaceStore: WorkspaceStore
    ) throws {
        try WorktreeContextRouter.switchConversation(
            conversationId: conversationId,
            toProjectPath: projectPath,
            chatStore: chatStore,
            projectContextStore: projectContextStore,
            workspaceStore: workspaceStore
        )
    }
}
