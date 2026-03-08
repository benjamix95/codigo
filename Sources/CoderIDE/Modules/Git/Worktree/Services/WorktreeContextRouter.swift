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
        let validatedProjectPath = try validatedRepositoryProjectPath(normalizedPath)
        guard !validatedProjectPath.isEmpty else {
            throw GitServiceError.commandFailed("Percorso progetto non valido.")
        }

        guard let contextId = projectContextStore.createOrReuseSingleProject(
            paths: [validatedProjectPath],
            suggestedName: (validatedProjectPath as NSString).lastPathComponent
        ) else {
            throw GitServiceError.commandFailed("Impossibile creare contesto progetto.")
        }

        chatStore.setContext(conversationId: conversationId, contextId: contextId)
        projectContextStore.activeContextId = contextId
        workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: contextId))
    }

    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path(percentEncoded: false)
    }

    private static func validatedRepositoryProjectPath(_ path: String) throws -> String {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitServiceError.commandFailed("Percorso progetto non valido.")
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw GitServiceError.commandFailed("Il percorso progetto non esiste o non è una directory.")
        }

        let resolvedRoot = try GitService().resolveGitRoot(from: path)
        let normalizedRoot = normalized(resolvedRoot)
        guard normalizedRoot == path else {
            throw GitServiceError.commandFailed(
                "Il percorso progetto deve puntare alla root del repository Git."
            )
        }
        return normalizedRoot
    }
}
