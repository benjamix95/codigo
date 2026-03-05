import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func handleProjectFolderSelection(result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let paths = urls.map { $0.path(percentEncoded: false) }
        guard let contextId = projectContextStore.createOrReuseSingleProject(paths: paths) else { return }
        projectContextStore.activeContextId = contextId
        projectContextStore.markAsRecentlyUsed(contextId: contextId)
        preferActiveContextForGlobalThread = true
        workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: contextId))
        let ctx = projectContextStore.context(id: contextId)
        let folderScope = (ctx?.folderPaths.count ?? 0) > 1 ? ctx?.activeFolderPath : nil
        if let selectedId = selectedConversationId,
           let selected = chatStore.conversation(for: selectedId),
           !selected.isArchived,
           !chatStore.hasUserMessages(selected) {
            if selected.contextId != contextId || selected.contextFolderPath != folderScope {
                chatStore.setContext(conversationId: selectedId, contextId: contextId)
                chatStore.setContextFolder(conversationId: selectedId, folderPath: folderScope)
            }
            selectedConversationId = selectedId
        } else if let reusable = chatStore.reusableEmptyConversation(contextId: contextId, contextFolderPath: folderScope) {
            selectedConversationId = reusable.id
        } else if let lastId = projectContextStore.lastActiveConversationId(contextId: contextId, folderPath: folderScope),
                  let lastConv = chatStore.conversation(for: lastId),
                  lastConv.contextId == contextId,
                  !lastConv.isArchived,
                  chatStore.hasUserMessages(lastConv) {
            selectedConversationId = lastId
        } else {
            selectedConversationId = chatStore.createConversation(contextId: contextId, contextFolderPath: folderScope)
        }
        syncThreadBoundProviderSelection(for: selectedConversationId)
    }
}
