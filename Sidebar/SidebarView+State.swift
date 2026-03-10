import SwiftUI
import AppKit
import CoderEngine

extension SidebarView {
    var selectedConversation: Conversation? {
        chatStore.conversation(for: selectedConversationId)
    }

    var isIDEMode: Bool {
        if let mode = selectedConversation?.mode {
            return mode == .ide
        }
        let pid = providerRegistry.selectedProviderId
        return ProviderSupport.isIDEProvider(id: pid) && !ProviderSupport.isAgentCompatibleProvider(id: pid)
    }

    /// Current project/workspace context. With no thread selected, keeps activeContextId
    /// so the project doesn't "close" when all conversations are deleted.
    var currentContext: ProjectContext? {
        let ctxId: UUID?
        if let selectedConversation {
            if let conversationContextId = selectedConversation.contextId {
                ctxId = conversationContextId
            } else {
                ctxId = preferActiveContextForGlobalThread ? projectContextStore.activeContextId : nil
            }
        } else {
            ctxId = projectContextStore.activeContextId
        }
        return projectContextStore.context(id: ctxId)
    }

    var orderedContexts: [ProjectContext] {
        projectContextStore.contexts.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var filteredContexts: [ProjectContext] {
        guard !sidebarQuery.isEmpty else { return orderedContexts }
        let q = sidebarQuery.lowercased()
        return orderedContexts.filter { $0.name.lowercased().contains(q) }
    }

    var visibleThreads: [Conversation] {
        if let contextId = currentContext?.id {
            return chatStore.conversations
                .filter { $0.contextId == contextId }
                .filter { showArchived || !$0.isArchived || $0.isFavorite }
                .filter { !favoritesOnly || $0.isFavorite }
                .filter { matchesQuery($0, query: sidebarQuery) }
                .sorted {
                    if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                    if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
                    return $0.createdAt > $1.createdAt
                }
        }
        return chatStore.conversations
            .filter { $0.contextId == nil }
            .filter { showArchived || !$0.isArchived || $0.isFavorite }
            .filter { !favoritesOnly || $0.isFavorite }
            .filter { matchesQuery($0, query: sidebarQuery) }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
                return $0.createdAt > $1.createdAt
            }
    }

    func groupedThreadsByFolder(from threads: [Conversation]) -> [(folder: String?, threads: [Conversation])] {
        guard let context = currentContext else { return [(nil, threads)] }
        var map: [String?: [Conversation]] = [:]
        for conv in threads {
            let key = context.folderPaths.contains(conv.contextFolderPath ?? "") ? conv.contextFolderPath : nil
            map[key, default: []].append(conv)
        }
        let orderedFolders = context.folderPaths.map(Optional.some)
        var result: [(String?, [Conversation])] = orderedFolders.compactMap { folder in
            guard let threads = map[folder], !threads.isEmpty else { return nil }
            return (folder, threads)
        }
        if let generic = map[nil], !generic.isEmpty {
            result.append((nil, generic))
        }
        return result
    }

    var currentContextSyncFingerprint: String {
        guard let context = currentContext else { return "none" }
        let folders = context.folderPaths.joined(separator: "|")
        let exclusions = context.excludedPaths.joined(separator: "|")
        let activeRoot = context.activeFolderPath ?? ""
        return "\(context.id.uuidString)#\(folders)#\(exclusions)#\(activeRoot)"
    }
}

// MARK: - Workspace Sync

extension SidebarView {
    func scheduleSidebarWorkspaceSync(currentContextId: UUID?) {
        DispatchQueue.main.async {
            projectContextStore.ensureWorkspaceContexts(workspaceStore.workspaces)
            let context = projectContextStore.context(id: currentContextId)
            workspaceStore.syncActiveWorkspace(with: context)
        }
    }
}
