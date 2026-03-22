import Foundation

struct SidebarThreadMetrics {
    let messageCount: Int
    let linesAdded: Int
    let linesRemoved: Int
    let fileCount: Int

    var hasDiffStats: Bool {
        linesAdded > 0 || linesRemoved > 0
    }

    static let empty = SidebarThreadMetrics(
        messageCount: 0, linesAdded: 0, linesRemoved: 0, fileCount: 0
    )

    @MainActor
    static func compute(
        conversation: Conversation,
        toolTraceStore: ToolTraceStore
    ) -> SidebarThreadMetrics {
        let totalMessages = conversation.messages.count

        let allEvents = toolTraceStore.allEvents(conversationId: conversation.id)
        guard !allEvents.isEmpty else {
            return SidebarThreadMetrics(
                messageCount: totalMessages, linesAdded: 0, linesRemoved: 0, fileCount: 0
            )
        }

        let fileChanges = ToolTraceFileChangeMapper.collect(from: allEvents)
        let linesAdded = fileChanges.reduce(0) { $0 + max(0, $1.added) }
        let linesRemoved = fileChanges.reduce(0) { $0 + max(0, $1.removed) }

        return SidebarThreadMetrics(
            messageCount: totalMessages,
            linesAdded: linesAdded,
            linesRemoved: linesRemoved,
            fileCount: fileChanges.count
        )
    }
}
