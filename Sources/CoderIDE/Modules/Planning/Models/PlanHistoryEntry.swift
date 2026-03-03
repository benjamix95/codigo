import Foundation

struct PlanHistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var conversationId: UUID
    var contextId: UUID?
    var contextFolderPath: String?
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var markdown: String
    var options: [PlanOption]
    var chosenPath: String?
    var tags: [String]
    var sourceMessageId: UUID?
    var isPinned: Bool
    var rebuildCount: Int
    var lastBuildAt: Date?

    init(
        id: UUID = UUID(),
        conversationId: UUID,
        contextId: UUID?,
        contextFolderPath: String?,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        title: String,
        markdown: String,
        options: [PlanOption],
        chosenPath: String?,
        tags: [String] = [],
        sourceMessageId: UUID? = nil,
        isPinned: Bool = false,
        rebuildCount: Int = 0,
        lastBuildAt: Date? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.contextId = contextId
        self.contextFolderPath = contextFolderPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.markdown = markdown
        self.options = options
        self.chosenPath = chosenPath
        self.tags = tags
        self.sourceMessageId = sourceMessageId
        self.isPinned = isPinned
        self.rebuildCount = rebuildCount
        self.lastBuildAt = lastBuildAt
    }
}
