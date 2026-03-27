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

enum SidebarThreadSnapshotBuilder {
    private struct SnapshotUpdate {
        let snapshot: SidebarThreadListSnapshot
        let fingerprint: SidebarThreadSnapshotFingerprint
    }

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
    private static func snapshotUpdate(
        from filteredThreads: [Conversation],
        contextId: UUID?,
        query: String,
        showArchived: Bool,
        favoritesOnly: Bool,
        chatStore: ChatStore
    ) -> SnapshotUpdate {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

        return SnapshotUpdate(
            snapshot: SidebarThreadListSnapshot(
                threads: filteredThreads,
                pinnedThreads: pinnedThreads,
                dateBuckets: dateBuckets,
                aiSearchHits: aiSearchHits
            ),
            fingerprint: SidebarThreadSnapshotFingerprint(
                contextId: contextId,
                query: normalizedQuery,
                showArchived: showArchived,
                favoritesOnly: favoritesOnly,
                threads: filteredThreads.map { conversation in
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
            )
        )
    }

    @MainActor
    static func build(
        chatStore: ChatStore,
        contextId: UUID?,
        query: String,
        showArchived: Bool,
        favoritesOnly: Bool
    ) -> SidebarThreadListSnapshot {
        let filteredThreads = filteredThreads(
            chatStore: chatStore,
            contextId: contextId,
            query: query,
            showArchived: showArchived,
            favoritesOnly: favoritesOnly
        )
        return snapshotUpdate(
            from: filteredThreads,
            contextId: contextId,
            query: query,
            showArchived: showArchived,
            favoritesOnly: favoritesOnly,
            chatStore: chatStore
        ).snapshot
    }

    @MainActor
    static func snapshotFingerprint(
        chatStore: ChatStore,
        contextId: UUID?,
        query: String,
        showArchived: Bool,
        favoritesOnly: Bool
    ) -> SidebarThreadSnapshotFingerprint {
        let filteredThreads = filteredThreads(
            chatStore: chatStore,
            contextId: contextId,
            query: query,
            showArchived: showArchived,
            favoritesOnly: favoritesOnly
        )
        return snapshotUpdate(
            from: filteredThreads,
            contextId: contextId,
            query: query,
            showArchived: showArchived,
            favoritesOnly: favoritesOnly,
            chatStore: chatStore
        ).fingerprint
    }

    @MainActor
    static func buildSnapshotAndFingerprint(
        chatStore: ChatStore,
        contextId: UUID?,
        query: String,
        showArchived: Bool,
        favoritesOnly: Bool
    ) -> (snapshot: SidebarThreadListSnapshot, fingerprint: SidebarThreadSnapshotFingerprint) {
        let filteredThreads = filteredThreads(
            chatStore: chatStore,
            contextId: contextId,
            query: query,
            showArchived: showArchived,
            favoritesOnly: favoritesOnly
        )
        let update = snapshotUpdate(
            from: filteredThreads,
            contextId: contextId,
            query: query,
            showArchived: showArchived,
            favoritesOnly: favoritesOnly,
            chatStore: chatStore
        )
        return (update.snapshot, update.fingerprint)
    }
}
