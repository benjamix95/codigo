import SwiftUI
import CoderEngine

// MARK: - Computed State

extension SidebarView {
    var activeContext: ProjectContext? {
        if let conversation = chatStore.conversation(for: selectedConversationId),
           let contextId = conversation.contextId {
            return projectContextStore.context(id: contextId)
        }
        if preferActiveContextForGlobalThread {
            return projectContextStore.activeContext
        }
        return nil
    }

    var orderedContexts: [ProjectContext] {
        projectContextStore.contexts.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var filteredContexts: [ProjectContext] {
        guard !query.isEmpty else { return orderedContexts }
        let q = query.lowercased()
        return orderedContexts.filter { $0.name.lowercased().contains(q) }
    }

    var visibleThreads: [Conversation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let contextId = activeContext?.id

        return chatStore.conversations
            .filter { conv in
                if let contextId { return conv.contextId == contextId }
                return conv.contextId == nil
            }
            .filter { showArchived || !$0.isArchived || $0.isFavorite }
            .filter { !favoritesOnly || $0.isFavorite }
            .filter { q.isEmpty || $0.title.lowercased().contains(q) }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
                return lhs.createdAt > rhs.createdAt
            }
    }
}

// MARK: - Actions

extension SidebarView {
    func attachConversation(to contextId: UUID) {
        projectContextStore.activeContextId = contextId
        projectContextStore.markAsRecentlyUsed(contextId: contextId)
        workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: contextId))

        let context = projectContextStore.context(id: contextId)
        let folderScope = scopedFolderPath(for: context)

        // Reuse current empty thread if possible
        if let selectedId = selectedConversationId,
           let selected = chatStore.conversation(for: selectedId),
           !selected.isArchived,
           !chatStore.hasUserMessages(selected) {
            if selected.contextId != contextId || selected.contextFolderPath != folderScope {
                chatStore.setContext(conversationId: selectedId, contextId: contextId)
                chatStore.setContextFolder(conversationId: selectedId, folderPath: folderScope)
            }
            return
        }

        // Try last active conversation
        if let lastId = projectContextStore.lastActiveConversationId(contextId: contextId, folderPath: folderScope),
           let lastConv = chatStore.conversation(for: lastId),
           lastConv.contextId == contextId,
           !lastConv.isArchived,
           chatStore.hasUserMessages(lastConv) {
            selectedConversationId = lastId
        } else {
            selectedConversationId = chatStore.createConversation(contextId: contextId, contextFolderPath: folderScope)
        }
    }

    func createThread(contextId: UUID?) {
        let effectiveContextId = contextId ?? activeContext?.id
        let context = projectContextStore.context(id: effectiveContextId)
        let folderScope = scopedFolderPath(for: context)

        if let reusable = chatStore.reusableEmptyConversation(
            contextId: effectiveContextId,
            contextFolderPath: folderScope,
            mode: nil
        ) {
            selectedConversationId = reusable.id
        } else {
            selectedConversationId = chatStore.createConversation(
                contextId: effectiveContextId,
                contextFolderPath: folderScope
            )
        }
        if let effectiveContextId {
            projectContextStore.activeContextId = effectiveContextId
            workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: effectiveContextId))
        }
    }

    func selectConversation(_ conversation: Conversation) {
        selectedConversationId = conversation.id
        if let contextId = conversation.contextId {
            projectContextStore.activeContextId = contextId
            projectContextStore.markAsRecentlyUsed(contextId: contextId)
            workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: contextId))
            if conversation.messages.contains(where: { $0.role == .user }) {
                projectContextStore.setLastActiveConversation(
                    contextId: contextId,
                    folderPath: conversation.contextFolderPath,
                    conversationId: conversation.id
                )
            }
        }
    }

    func clearConversationContext() {
        guard let convId = selectedConversationId else { return }
        chatStore.setContext(conversationId: convId, contextId: nil)
        projectContextStore.activeContextId = nil
    }

    func deleteContext(_ context: ProjectContext) {
        chatStore.clearWorkspaceReferences(workspaceId: context.id)
        workspaceStore.delete(id: context.id)
        projectContextStore.remove(id: context.id)
        if activeContext?.id == context.id {
            clearConversationContext()
        }
    }

    func scopedFolderPath(for context: ProjectContext?) -> String? {
        guard let context else { return nil }
        return context.folderPaths.count > 1 ? context.activeFolderPath : nil
    }

}

// MARK: - Date Formatting

extension SidebarView {
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en_US")
        f.unitsStyle = .short
        return f
    }()

    func relativeDate(_ date: Date, relativeTo ref: Date = Date()) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: ref)
    }
}
