import Foundation
import CoderEngine

struct Conversation: Identifiable, Codable {
    let id: UUID
    var threadRootConversationId: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var contextId: UUID?
    var contextFolderPath: String?
    var mode: CoderMode?
    var preferredProviderId: String?
    var contextMemorySummaryMarkdown: String?
    var contextMemoryGeneratedAt: Date?
    var contextMemorySourceMessageCount: Int?
    var isArchived: Bool
    var isPinned: Bool
    var isFavorite: Bool

    /// Last input_tokens reported by the API for this conversation (real usage, not heuristic).
    var lastInputTokens: Int?

    // Legacy fields kept for one release migration path.
    var workspaceId: UUID?
    var adHocFolderPaths: [String]
    var checkpoints: [ConversationCheckpoint]

    init(
        id: UUID = UUID(),
        threadRootConversationId: UUID? = nil,
        title: String = "New conversation",
        messages: [ChatMessage] = [],
        createdAt: Date = .now,
        contextId: UUID? = nil,
        contextFolderPath: String? = nil,
        mode: CoderMode? = nil,
        preferredProviderId: String? = nil,
        contextMemorySummaryMarkdown: String? = nil,
        contextMemoryGeneratedAt: Date? = nil,
        contextMemorySourceMessageCount: Int? = nil,
        isArchived: Bool = false,
        isPinned: Bool = false,
        isFavorite: Bool = false,
        lastInputTokens: Int? = nil,
        workspaceId: UUID? = nil,
        adHocFolderPaths: [String] = [],
        checkpoints: [ConversationCheckpoint] = []
    ) {
        self.id = id
        self.threadRootConversationId = threadRootConversationId ?? id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.contextId = contextId
        self.contextFolderPath = contextFolderPath
        self.mode = mode
        self.preferredProviderId = preferredProviderId
        self.contextMemorySummaryMarkdown = contextMemorySummaryMarkdown
        self.contextMemoryGeneratedAt = contextMemoryGeneratedAt
        self.contextMemorySourceMessageCount = contextMemorySourceMessageCount
        self.isArchived = isArchived
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.lastInputTokens = lastInputTokens
        self.workspaceId = workspaceId
        self.adHocFolderPaths = adHocFolderPaths
        self.checkpoints = checkpoints
    }

    private enum CodingKeys: String, CodingKey {
        case id, threadRootConversationId, title, messages, createdAt, contextId, contextFolderPath, mode, preferredProviderId, contextMemorySummaryMarkdown, contextMemoryGeneratedAt, contextMemorySourceMessageCount, isArchived, isPinned, isFavorite, lastInputTokens, workspaceId, adHocFolderPaths, checkpoints
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        threadRootConversationId = (try? c.decode(UUID.self, forKey: .threadRootConversationId)) ?? id
        title = try c.decode(String.self, forKey: .title)
        messages = try c.decode([ChatMessage].self, forKey: .messages)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        contextId = try? c.decode(UUID.self, forKey: .contextId)
        contextFolderPath = try? c.decode(String.self, forKey: .contextFolderPath)
        isArchived = (try? c.decode(Bool.self, forKey: .isArchived)) ?? false
        isPinned = (try? c.decode(Bool.self, forKey: .isPinned)) ?? false
        isFavorite = (try? c.decode(Bool.self, forKey: .isFavorite)) ?? false
        workspaceId = try? c.decode(UUID.self, forKey: .workspaceId)
        adHocFolderPaths = (try? c.decode([String].self, forKey: .adHocFolderPaths)) ?? []
        checkpoints = (try? c.decode([ConversationCheckpoint].self, forKey: .checkpoints)) ?? []
        if let raw = try? c.decode(String.self, forKey: .mode), let m = CoderMode(rawValue: raw) {
            mode = m
        } else {
            mode = nil
        }
        preferredProviderId = try? c.decode(String.self, forKey: .preferredProviderId)
        contextMemorySummaryMarkdown = try? c.decode(String.self, forKey: .contextMemorySummaryMarkdown)
        contextMemoryGeneratedAt = try? c.decode(Date.self, forKey: .contextMemoryGeneratedAt)
        contextMemorySourceMessageCount = try? c.decode(Int.self, forKey: .contextMemorySourceMessageCount)
        lastInputTokens = try? c.decode(Int.self, forKey: .lastInputTokens)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(threadRootConversationId, forKey: .threadRootConversationId)
        try c.encode(title, forKey: .title)
        try c.encode(messages, forKey: .messages)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(contextId, forKey: .contextId)
        try c.encode(contextFolderPath, forKey: .contextFolderPath)
        try c.encode(mode?.rawValue, forKey: .mode)
        try c.encodeIfPresent(preferredProviderId, forKey: .preferredProviderId)
        try c.encodeIfPresent(contextMemorySummaryMarkdown, forKey: .contextMemorySummaryMarkdown)
        try c.encodeIfPresent(contextMemoryGeneratedAt, forKey: .contextMemoryGeneratedAt)
        try c.encodeIfPresent(contextMemorySourceMessageCount, forKey: .contextMemorySourceMessageCount)
        try c.encode(isArchived, forKey: .isArchived)
        try c.encode(isPinned, forKey: .isPinned)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encodeIfPresent(lastInputTokens, forKey: .lastInputTokens)

        // Legacy compatibility (1 release)
        try c.encode(workspaceId, forKey: .workspaceId)
        try c.encode(adHocFolderPaths, forKey: .adHocFolderPaths)
        try c.encode(checkpoints, forKey: .checkpoints)
    }
}

struct ConversationCheckpointGitState: Codable, Equatable {
    let gitRootPath: String
    let gitSnapshotRef: String
}

struct ConversationCheckpoint: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let messageCount: Int
    let planBoardSnapshot: PlanBoard?
    /// Optional snapshot for a second plan conversation (used by plan-build turns
    /// where execution happens in agent conversation but plan board lives elsewhere).
    let linkedPlanConversationId: UUID?
    let linkedPlanBoardSnapshot: PlanBoard?
    let gitStates: [ConversationCheckpointGitState]

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        messageCount: Int,
        planBoardSnapshot: PlanBoard?,
        linkedPlanConversationId: UUID? = nil,
        linkedPlanBoardSnapshot: PlanBoard? = nil,
        gitStates: [ConversationCheckpointGitState]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.messageCount = messageCount
        self.planBoardSnapshot = planBoardSnapshot
        self.linkedPlanConversationId = linkedPlanConversationId
        self.linkedPlanBoardSnapshot = linkedPlanBoardSnapshot
        self.gitStates = gitStates
    }
}

struct ThreadSearchHit: Identifiable {
    let id: UUID
    let conversationId: UUID
    let title: String
    let snippet: String
    let matchCount: Int
    let isArchived: Bool
    let isFavorite: Bool
}
