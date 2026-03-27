import Foundation

struct SidebarThreadMetrics: Equatable {
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
        let summary = toolTraceStore.conversationFileChangeSummary(conversationId: conversation.id)
        guard summary.fileCount > 0 || summary.linesAdded > 0 || summary.linesRemoved > 0 else {
            return SidebarThreadMetrics(
                messageCount: totalMessages, linesAdded: 0, linesRemoved: 0, fileCount: 0
            )
        }

        return SidebarThreadMetrics(
            messageCount: totalMessages,
            linesAdded: summary.linesAdded,
            linesRemoved: summary.linesRemoved,
            fileCount: summary.fileCount
        )
    }
}
