import Foundation

// MARK: - Timeline Ordering

enum ChatTurnTimelineOrdering {
    static func visibleBlocks(
        from blocks: [PersistedChatTimelineBlock]
    ) -> [PersistedChatTimelineBlock] {
        blocks.filter { block in
            block.kind != .toolTrace
                && block.kind != .commands
                && block.kind != .files
                && block.kind != .status
        }
    }

    static func narrativeBlocks(
        from visibleBlocks: [PersistedChatTimelineBlock]
    ) -> [PersistedChatTimelineBlock] {
        visibleBlocks.filter { $0.kind == .reasoning }
    }

    static func detailBlocks(
        from visibleBlocks: [PersistedChatTimelineBlock]
    ) -> [PersistedChatTimelineBlock] {
        visibleBlocks.filter { $0.kind != .primaryText && $0.kind != .reasoning }
    }
}
