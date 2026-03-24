import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    func openExternalURL(_ urlString: String) {
        guard let url = AppUpdateCenter.validatedHTTPSURL(from: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Unified Folder Picker

    func handleUnifiedFolderSelection(result: Result<[URL], Error>) {
        let kind = panelCoordinator.pendingFolderPickerKind
        panelCoordinator.pendingFolderPickerKind = .none

        switch kind {
        case .openProject:
            handleProjectFolderSelection(result: result)
        case .addFolderToContext(let contextId):
            handleAddFolderToContext(contextId: contextId, result: result)
        case .none:
            break
        }
    }

    // MARK: - Open Project

    func handleProjectFolderSelection(result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let paths = urls.map { $0.path(percentEncoded: false) }
        guard let contextId = projectContextStore.createOrReuseSingleProject(paths: paths) else { return }
        projectContextStore.activeContextId = contextId
        projectContextStore.markAsRecentlyUsed(contextId: contextId)
        panelCoordinator.preferActiveContextForGlobalThread = true
        workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: contextId))
        let ctx = projectContextStore.context(id: contextId)
        let folderScope = (ctx?.folderPaths.count ?? 0) > 1 ? ctx?.activeFolderPath : nil
        if let selectedId = panelCoordinator.selectedConversationId,
           let selected = chatStore.conversation(for: selectedId),
           !selected.isArchived,
           !chatStore.hasUserMessages(selected) {
            if selected.contextId != contextId || selected.contextFolderPath != folderScope {
                chatStore.setContext(conversationId: selectedId, contextId: contextId)
                chatStore.setContextFolder(conversationId: selectedId, folderPath: folderScope)
            }
            panelCoordinator.selectedConversationId = selectedId
        } else if let reusable = chatStore.reusableEmptyConversation(contextId: contextId, contextFolderPath: folderScope) {
            panelCoordinator.selectedConversationId = reusable.id
        } else if let lastId = projectContextStore.lastActiveConversationId(contextId: contextId, folderPath: folderScope),
                  let lastConv = chatStore.conversation(for: lastId),
                  lastConv.contextId == contextId,
                  !lastConv.isArchived,
                  chatStore.hasUserMessages(lastConv) {
            panelCoordinator.selectedConversationId = lastId
        } else {
            panelCoordinator.selectedConversationId = chatStore.createConversation(contextId: contextId, contextFolderPath: folderScope)
        }
        syncThreadBoundProviderSelection(for: panelCoordinator.selectedConversationId)
    }

    // MARK: - Add Folder to Context

    func handleAddFolderToContext(contextId: UUID, result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let normalizedPath = workspaceStore.normalizedWorkspacePath(url.path(percentEncoded: false))
        guard !normalizedPath.isEmpty else { return }
        guard var context = projectContextStore.context(id: contextId) else { return }
        guard !context.folderPaths.contains(where: {
            workspaceStore.normalizedWorkspacePath($0) == normalizedPath
        }) else { return }
        context.folderPaths.append(normalizedPath)
        context.lastActiveFolderPath = normalizedPath
        context.updatedAt = .now
        projectContextStore.upsert(context)
        workspaceStore.syncActiveWorkspace(with: context)
        if let selectedId = panelCoordinator.selectedConversationId {
            let folderScope = context.folderPaths.count > 1 ? context.activeFolderPath : nil
            chatStore.setContextFolder(conversationId: selectedId, folderPath: folderScope)
        }
    }
}
