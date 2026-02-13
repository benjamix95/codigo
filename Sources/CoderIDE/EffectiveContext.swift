import SwiftUI
import CoderEngine

/// Contesto effettivo per la conversazione selezionata (workspace o ad-hoc)
struct EffectiveContext {
    let folderPaths: [String]
    let isWorkspace: Bool
    let workspace: Workspace?
    
    var hasContext: Bool {
        !folderPaths.isEmpty
    }
    
    var primaryPath: String? {
        folderPaths.first
    }
    
    var displayLabel: String {
        if let ws = workspace {
            return ws.name
        }
        if folderPaths.count == 1 {
            return (folderPaths[0] as NSString).lastPathComponent
        }
        if !folderPaths.isEmpty {
            return "Progetto (\(folderPaths.count) cartelle)"
        }
        return "Nessun progetto"
    }
    
    /// Costruisce WorkspaceContext per i provider
    func toWorkspaceContext(openFiles: [OpenFile] = [], activeSelection: String? = nil, activeFilePath: String? = nil) -> WorkspaceContext {
        let urls = folderPaths.map { URL(fileURLWithPath: $0) }
        let excluded = workspace?.excludedPaths ?? []
        return WorkspaceContext(
            workspacePaths: urls.isEmpty ? [URL(fileURLWithPath: "/tmp")] : urls,
            isNamedWorkspace: isWorkspace,
            workspaceName: workspace?.name,
            excludedPaths: excluded,
            openFiles: openFiles,
            activeSelection: activeSelection,
            activeFilePath: activeFilePath
        )
    }
    
    static func empty() -> EffectiveContext {
        EffectiveContext(folderPaths: [], isWorkspace: false, workspace: nil)
    }
}

/// Helper per calcolare EffectiveContext da conversation + workspaceStore
@MainActor
func effectiveContext(
    for conversationId: UUID?,
    chatStore: ChatStore,
    workspaceStore: WorkspaceStore
) -> EffectiveContext {
    guard let conv = chatStore.conversation(for: conversationId) else {
        return .empty()
    }
    
    if let wsId = conv.workspaceId,
       let ws = workspaceStore.workspaces.first(where: { $0.id == wsId }) {
        return EffectiveContext(
            folderPaths: ws.folderPaths,
            isWorkspace: true,
            workspace: ws
        )
    }
    
    if !conv.adHocFolderPaths.isEmpty {
        return EffectiveContext(
            folderPaths: conv.adHocFolderPaths,
            isWorkspace: false,
            workspace: nil
        )
    }
    
    return .empty()
}
