import SwiftUI
import CoderEngine

enum ContextScopeMode: String, CaseIterable {
    case auto
    case activeFolder
    case workspaceAll

    var label: String {
        switch self {
        case .auto: return "Auto (smart)"
        case .activeFolder: return "Folder"
        case .workspaceAll: return "Workspace"
        }
    }

    var helpText: String {
        switch self {
        case .auto:
            return "Use the active folder; if open context indicates dependencies outside scope, automatically widen to the entire workspace."
        case .activeFolder:
            return "Limit agent context to the active folder only."
        case .workspaceAll:
            return "Provide all workspace folders to the agent."
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
            return "Project (\(folderPaths.count) folders)"
        }
        return "No project"
    }

    func toWorkspaceContext(
        openFiles: [OpenFile] = [],
        activeSelection: String? = nil,
        activeFilePath: String? = nil,
        scopeMode: ContextScopeMode = .auto,
        preferDebuggerPromptProfile: Bool = false
    ) -> WorkspaceContext {
        let scopedPaths: [String]

        // Multi-folder workspace: always expose all folders so the LLM knows the full structure
        // and tools (grep, codebase_search, semantic_search) can work across the entire workspace.
        if folderPaths.count > 1 {
            scopedPaths = folderPaths
        } else {
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
            activeRootPath: activeRootPath,
            preferDebuggerPromptProfile: preferDebuggerPromptProfile
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
    projectContextStore: ProjectContextStore,
    preferActiveContextForGlobalThread: Bool = true
) -> EffectiveContext {
    let contextId: UUID?
    if let conv = chatStore.conversation(for: conversationId) {
        if let conversationContextId = conv.contextId {
            contextId = conversationContextId
        } else {
            // Global thread (contextId nil): optionally inherit active project.
            contextId = preferActiveContextForGlobalThread ? projectContextStore.activeContextId : nil
        }
    } else {
        // No selected conversation (e.g. all deleted): keep current project context.
        contextId = projectContextStore.activeContextId
    }

    if let contextId, let context = projectContextStore.context(id: contextId) {
        return EffectiveContext(
            contextId: context.id,
            folderPaths: context.folderPaths,
            isWorkspace: context.kind == .workspace,
            context: context
        )
    }

    return .empty()
}
