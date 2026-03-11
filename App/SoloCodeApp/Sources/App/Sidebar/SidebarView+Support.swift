import SwiftUI
import CoderEngine

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
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var visibleThreads: [Conversation] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return chatStore.conversations
            .filter { !$0.isArchived }
            .filter { conversation in
                if let contextId = activeContext?.id {
                    return conversation.contextId == contextId
                }
                return conversation.contextId == nil
            }
            .filter { conversation in
                normalizedQuery.isEmpty || conversation.title.lowercased().contains(normalizedQuery)
            }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned && !rhs.isPinned
                }
                if lhs.isFavorite != rhs.isFavorite {
                    return lhs.isFavorite && !rhs.isFavorite
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    func attachConversation(to contextId: UUID) {
        projectContextStore.activeContextId = contextId
        projectContextStore.markAsRecentlyUsed(contextId: contextId)
        workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: contextId))
        createThread(contextId: contextId)
    }

    func createThread(contextId: UUID?) {
        let context = projectContextStore.context(id: contextId)
        let folderScope = context?.folderPaths.count ?? 0 > 1 ? context?.activeFolderPath : nil
        if let reusable = chatStore.reusableEmptyConversation(
            contextId: contextId,
            contextFolderPath: folderScope
        ) {
            selectedConversationId = reusable.id
        } else {
            selectedConversationId = chatStore.createConversation(
                contextId: contextId,
                contextFolderPath: folderScope
            )
        }
        if let contextId {
            projectContextStore.activeContextId = contextId
            workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: contextId))
        }
    }

    func selectConversation(_ conversation: Conversation) {
        selectedConversationId = conversation.id
        if let contextId = conversation.contextId {
            projectContextStore.activeContextId = contextId
            projectContextStore.markAsRecentlyUsed(contextId: contextId)
            workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: contextId))
        }
    }

    func icon(for conversation: Conversation) -> String {
        if conversation.isFavorite { return "star.fill" }
        if conversation.isPinned { return "pin.fill" }
        return "bubble.left.and.bubble.right"
    }

    func color(for conversation: Conversation) -> Color {
        if conversation.isFavorite { return .yellow }
        if conversation.isPinned { return .orange }
        return .secondary
    }

    func threadSubtitle(_ conversation: Conversation) -> String {
        if let folder = conversation.contextFolderPath {
            return (folder as NSString).lastPathComponent
        }
        if let contextId = conversation.contextId,
           let context = projectContextStore.context(id: contextId) {
            return context.name
        }
        return "Global"
    }

    func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.4)
    }

    func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    func label(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}
