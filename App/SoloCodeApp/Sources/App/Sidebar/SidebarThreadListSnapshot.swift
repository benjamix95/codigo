import Foundation
import CoderEngine

struct SidebarThreadDateBucket: Identifiable {
    let group: SidebarDateGroup
    let threads: [Conversation]

    var id: String { group.rawValue }
}

struct SidebarThreadListSnapshot {
    let threads: [Conversation]
    let pinnedThreads: [Conversation]
    let dateBuckets: [SidebarThreadDateBucket]
    let aiSearchHits: [ThreadSearchHit]

    static let empty = SidebarThreadListSnapshot(
        threads: [],
        pinnedThreads: [],
        dateBuckets: [],
        aiSearchHits: []
    )
}

struct SidebarThreadRenderState {
    let hasDraft: Bool
    let isActive: Bool
    let isStreaming: Bool
    let statusText: String?
    let todoProgressLabel: String?
    let metrics: SidebarThreadMetrics

    static let empty = SidebarThreadRenderState(
        hasDraft: false,
        isActive: false,
        isStreaming: false,
        statusText: nil,
        todoProgressLabel: nil,
        metrics: .empty
    )
}

struct SidebarThreadSnapshotFingerprint: Equatable {
    let contextId: UUID?
    let query: String
    let showArchived: Bool
    let favoritesOnly: Bool
    let threads: [Thread]

    struct Thread: Equatable {
        let id: UUID
        let title: String
        let isPinned: Bool
        let isFavorite: Bool
        let isArchived: Bool
        let contextId: UUID?
        let contextFolderPath: String?
        let createdAt: Date
    }
}

struct SidebarThreadRenderFingerprint: Equatable {
    let threads: [Thread]

    struct Thread: Equatable {
        let id: UUID
        let hasDraft: Bool
        let isActive: Bool
        let isStreaming: Bool
        let statusText: String?
        let todoProgressLabel: String?
        let metrics: SidebarThreadMetrics
    }
}

enum SidebarThreadSnapshotBuilder {
    @MainActor
    private static func filteredThreads(
        chatStore: ChatStore,
        contextId: UUID?,
        query: String,
        showArchived: Bool,
        favoritesOnly: Bool
    ) -> [Conversation] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return chatStore.conversations
            .filter { conversation in
                if let contextId {
                    return conversation.contextId == contextId
                }
                return conversation.contextId == nil
            }
            .filter { showArchived || !$0.isArchived || $0.isFavorite }
            .filter { !favoritesOnly || $0.isFavorite }
            .filter { normalizedQuery.isEmpty || $0.title.lowercased().contains(normalizedQuery) }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
                return lhs.createdAt > rhs.createdAt
            }
    }

    @MainActor
    static func build(
        chatStore: ChatStore,
        contextId: UUID?,
        query: String,
        showArchived: Bool,
        favoritesOnly: Bool
    ) -> SidebarThreadListSnapshot {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredThreads = filteredThreads(
            chatStore: chatStore,
            contextId: contextId,
            query: query,
            showArchived: showArchived,
            favoritesOnly: favoritesOnly
        )

        let pinnedThreads = filteredThreads.filter(\.isPinned)
        let dateBuckets = SidebarDateGrouper.group(filteredThreads.filter { !$0.isPinned }).map {
            SidebarThreadDateBucket(group: $0.group, threads: $0.threads)
        }
        let aiSearchHits: [ThreadSearchHit]
        if normalizedQuery.count >= 2 {
            aiSearchHits = chatStore.searchThreads(
                query: normalizedQuery,
                includeArchived: true,
                limit: 12
            )
        } else {
            aiSearchHits = []
        }

        return SidebarThreadListSnapshot(
            threads: filteredThreads,
            pinnedThreads: pinnedThreads,
            dateBuckets: dateBuckets,
            aiSearchHits: aiSearchHits
        )
    }

    @MainActor
    static func snapshotFingerprint(
        chatStore: ChatStore,
        contextId: UUID?,
        query: String,
        showArchived: Bool,
        favoritesOnly: Bool
    ) -> SidebarThreadSnapshotFingerprint {
        let threads = filteredThreads(
            chatStore: chatStore,
            contextId: contextId,
            query: query,
            showArchived: showArchived,
            favoritesOnly: favoritesOnly
        ).map { conversation in
            SidebarThreadSnapshotFingerprint.Thread(
                id: conversation.id,
                title: conversation.title,
                isPinned: conversation.isPinned,
                isFavorite: conversation.isFavorite,
                isArchived: conversation.isArchived,
                contextId: conversation.contextId,
                contextFolderPath: conversation.contextFolderPath,
                createdAt: conversation.createdAt
            )
        }
        return SidebarThreadSnapshotFingerprint(
            contextId: contextId,
            query: query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            showArchived: showArchived,
            favoritesOnly: favoritesOnly,
            threads: threads
        )
    }

    @MainActor
    static func buildRenderStates(
        conversations: [Conversation],
        chatStore: ChatStore,
        todoStore: TodoStore,
        toolTraceStore: ToolTraceStore
    ) -> [UUID: SidebarThreadRenderState] {
        Dictionary(uniqueKeysWithValues: conversations.map { conversation in
            let hasDraft = !(chatStore.draftTexts[conversation.id]?
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let isActive = chatStore.isTaskActive(for: conversation.id)
            let isStreaming = chatStore.isAssistantStreaming(in: conversation.id)
            let chatTodos = todoStore.displayTodosForChat(for: conversation.id)
            let renderState = SidebarThreadRenderState(
                hasDraft: hasDraft,
                isActive: isActive,
                isStreaming: isStreaming,
                statusText: chatStore.taskStatusTexts[conversation.id],
                todoProgressLabel: SidebarThreadTodoCaption.progressLabel(displayTodos: chatTodos),
                metrics: SidebarThreadMetrics.compute(
                    conversation: conversation,
                    toolTraceStore: toolTraceStore
                )
            )
            return (conversation.id, renderState)
        })
    }

    @MainActor
    static func renderFingerprint(
        conversations: [Conversation],
        chatStore: ChatStore,
        todoStore: TodoStore,
        toolTraceStore: ToolTraceStore
    ) -> SidebarThreadRenderFingerprint {
        let threads = conversations.map { conversation in
            let renderState = buildRenderState(
                for: conversation,
                chatStore: chatStore,
                todoStore: todoStore,
                toolTraceStore: toolTraceStore
            )
            return SidebarThreadRenderFingerprint.Thread(
                id: conversation.id,
                hasDraft: renderState.hasDraft,
                isActive: renderState.isActive,
                isStreaming: renderState.isStreaming,
                statusText: renderState.statusText,
                todoProgressLabel: renderState.todoProgressLabel,
                metrics: renderState.metrics
            )
        }
        return SidebarThreadRenderFingerprint(threads: threads)
    }

    @MainActor
    private static func buildRenderState(
        for conversation: Conversation,
        chatStore: ChatStore,
        todoStore: TodoStore,
        toolTraceStore: ToolTraceStore
    ) -> SidebarThreadRenderState {
        let hasDraft = !(chatStore.draftTexts[conversation.id]?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let isActive = chatStore.isTaskActive(for: conversation.id)
        let isStreaming = chatStore.isAssistantStreaming(in: conversation.id)
        let chatTodos = todoStore.displayTodosForChat(for: conversation.id)
        return SidebarThreadRenderState(
            hasDraft: hasDraft,
            isActive: isActive,
            isStreaming: isStreaming,
            statusText: chatStore.taskStatusTexts[conversation.id],
            todoProgressLabel: SidebarThreadTodoCaption.progressLabel(displayTodos: chatTodos),
            metrics: SidebarThreadMetrics.compute(
                conversation: conversation,
                toolTraceStore: toolTraceStore
            )
        )
    }
}
