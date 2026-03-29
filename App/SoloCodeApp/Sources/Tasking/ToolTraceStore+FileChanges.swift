import Foundation

extension ToolTraceStore {
    func conversationLatestFileChange(conversationId: UUID) -> ToolTraceFileChange? {
        let events = allEvents(conversationId: conversationId)
        guard !events.isEmpty else { return nil }
        return ToolTraceFileChangeMapper.collect(from: events).latestChange()
    }

    func conversationLatestPreviewableFileChange(conversationId: UUID) -> ToolTraceFileChange? {
        let events = allEvents(conversationId: conversationId)
        guard !events.isEmpty else { return nil }
        return ToolTraceFileChangeMapper.collect(from: events).latestPreviewableChange()
    }
}
