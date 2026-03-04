import Foundation

enum WorktreeContextRouter {
    @MainActor
    static func switchConversation(
        conversationId: UUID?,
        toProjectPath projectPath: String,
        chatStore: ChatStore,
        projectContextStore: ProjectContextStore,
        workspaceStore: WorkspaceStore
    ) throws {
        guard let conversationId else {
            throw GitServiceError.commandFailed("Nessuna conversazione selezionata.")
        }

        let normalizedPath = normalized(projectPath)
        guard !normalizedPath.isEmpty else {
            throw GitServiceError.commandFailed("Percorso progetto non valido.")
        }

        guard let contextId = projectContextStore.createOrReuseSingleProject(
            paths: [normalizedPath],
            suggestedName: (normalizedPath as NSString).lastPathComponent
        ) else {
            throw GitServiceError.commandFailed("Impossibile creare contesto progetto.")
        }

        chatStore.setContext(conversationId: conversationId, contextId: contextId)
        projectContextStore.activeContextId = contextId

        if workspaceStore.workspaces.contains(where: { $0.id == contextId }) {
            workspaceStore.activeWorkspaceId = contextId
        } else {
            workspaceStore.activeWorkspaceId = nil
        }
        workspaceStore.save()
    }

    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path(percentEncoded: false)
    }
}
