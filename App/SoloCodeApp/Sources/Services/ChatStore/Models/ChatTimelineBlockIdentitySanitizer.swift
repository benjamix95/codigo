import Foundation

func sanitizeTimelineBlockIDs(_ blocks: [PersistedChatTimelineBlock]) -> [PersistedChatTimelineBlock] {
    var seenCounts: [String: Int] = [:]
    return blocks.map { block in
        let occurrence = seenCounts[block.id, default: 0]
        seenCounts[block.id] = occurrence + 1
        guard occurrence > 0 else { return block }
        return block.withID("\(block.id)__dup\(occurrence)-seq\(block.sequence)")
    }
}

private extension PersistedChatTimelineBlock {
    func withID(_ id: String) -> PersistedChatTimelineBlock {
        PersistedChatTimelineBlock(
            id: id,
            kind: kind,
            title: title,
            text: text,
            items: items,
            metadata: metadata,
            isCollapsible: isCollapsible,
            isCollapsedByDefault: isCollapsedByDefault,
            sequence: sequence
        )
    }
}
