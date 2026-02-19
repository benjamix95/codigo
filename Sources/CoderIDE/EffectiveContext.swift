import SwiftUI
import CoderEngine

enum ContextScopeMode: String, CaseIterable {
    case auto
    case activeFolder
    case workspaceAll

    var label: String {
        switch self {
        case .auto: return "Auto (smart)"
        case .activeFolder: return "Cartella"
        case .workspaceAll: return "Workspace"
        }
    }

    var helpText: String {
        switch self {
        case .auto:
            return "Usa la cartella attiva; se il contesto aperto indica dipendenze fuori scope, allarga automaticamente a tutto il workspace."
        case .activeFolder:
            return "Limita il contesto agente alla sola cartella attiva."
        case .workspaceAll:
            return "Fornisce all'agente tutte le cartelle del workspace."
        }
    }
}

struct EffectiveContext {
    let contextId: UUID?
    let folderPaths: [String]
    let isWorkspace: Bool
    let context: ProjectContext?

    var hasContext: Bool { !folderPaths.isEmpty }
    var primaryPath: String? { folderPaths.first }
    var activeRootPath: String? { context?.activeFolderPath ?? folderPaths.first }

    var displayLabel: String {
        if let context {
            return context.name
        }
        if folderPaths.count == 1 {
            return (folderPaths[0] as NSString).lastPathComponent
        }
        if !folderPaths.isEmpty {
            return "Progetto (\(folderPaths.count) cartelle)"
        }
        return "Nessun progetto"
    }

    func toWorkspaceContext(
        openFiles: [OpenFile] = [],
        activeSelection: String? = nil,
        activeFilePath: String? = nil,
        scopeMode: ContextScopeMode = .auto
    ) -> WorkspaceContext {
        let scopedPaths: [String]

        switch scopeMode {
        case .workspaceAll:
            scopedPaths = folderPaths
        case .activeFolder:
            if let activeRootPath, !activeRootPath.isEmpty {
                scopedPaths = [activeRootPath]
            } else {
                scopedPaths = folderPaths
            }
        case .auto:
            if shouldUseWorkspaceWideScope(openFiles: openFiles, activeFilePath: activeFilePath) {
                scopedPaths = folderPaths
            } else if let activeRootPath, !activeRootPath.isEmpty {
                scopedPaths = [activeRootPath]
            } else {
                scopedPaths = folderPaths
            }
        }

        let urls = scopedPaths.map { URL(fileURLWithPath: $0) }
        let excluded = context?.excludedPaths ?? []
        return WorkspaceContext(
            workspacePaths: urls.isEmpty ? [URL(fileURLWithPath: "/tmp")] : urls,
            isNamedWorkspace: isWorkspace,
            workspaceName: context?.name,
            excludedPaths: excluded,
            openFiles: openFiles,
            activeSelection: activeSelection,
            activeFilePath: activeFilePath,
            activeRootPath: activeRootPath
        )
    }

    private func shouldUseWorkspaceWideScope(openFiles: [OpenFile], activeFilePath: String?) -> Bool {
        guard let activeRoot = activeRootPath, folderPaths.count > 1 else { return false }

        if let activeFilePath, !activeFilePath.isEmpty, !activeFilePath.hasPrefix(activeRoot + "/"), activeFilePath != activeRoot {
            return true
        }
        if openFiles.contains(where: { !$0.path.hasPrefix(activeRoot + "/") && $0.path != activeRoot }) {
            return true
        }
        return false
    }

    static func empty() -> EffectiveContext {
        EffectiveContext(contextId: nil, folderPaths: [], isWorkspace: false, context: nil)
    }
}

@MainActor
func effectiveContext(
    for conversationId: UUID?,
    chatStore: ChatStore,
    projectContextStore: ProjectContextStore
) -> EffectiveContext {
    guard let conv = chatStore.conversation(for: conversationId) else {
        return .empty()
    }

    if let context = projectContextStore.context(id: conv.contextId) {
        return EffectiveContext(
            contextId: context.id,
            folderPaths: context.folderPaths,
            isWorkspace: context.kind == .workspace,
            context: context
        )
    }

    return .empty()
}
