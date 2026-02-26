import SwiftUI
import CoderEngine

struct PlanAttachment: Codable, Equatable {
    var historyEntryId: UUID
    var layoutVersion: Int
    var showExpand: Bool
    var snapshotTitle: String
}

enum ChatAttachmentKind: String, Codable {
    case image
    case document
    case file
}

struct ChatAttachment: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: ChatAttachmentKind
    var originalName: String
    var mimeType: String?
    var localPath: String
    var sizeBytes: Int64?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: ChatAttachmentKind,
        originalName: String,
        mimeType: String? = nil,
        localPath: String,
        sizeBytes: Int64? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.originalName = originalName
        self.mimeType = mimeType
        self.localPath = localPath
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
    }
}

struct ChatMessage: Identifiable, Codable {
    var id: UUID
    var role: Role
    var content: String
    var isStreaming: Bool
    var imagePaths: [String]?
    var attachments: [ChatAttachment]?
    var planAttachment: PlanAttachment?

    enum Role: String, Codable {
        case user
        case assistant
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        isStreaming: Bool = false,
        imagePaths: [String]? = nil,
        attachments: [ChatAttachment]? = nil,
        planAttachment: PlanAttachment? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.imagePaths = imagePaths
        if let attachments {
            self.attachments = attachments
        } else if let imagePaths, !imagePaths.isEmpty {
            self.attachments = imagePaths.map { path in
                ChatAttachment(
                    kind: .image,
                    originalName: URL(fileURLWithPath: path).lastPathComponent,
                    mimeType: nil,
                    localPath: path
                )
            }
        } else {
            self.attachments = nil
        }
        self.planAttachment = planAttachment
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, isStreaming, imagePaths, attachments, planAttachment
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(Role.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
        isStreaming = (try? c.decode(Bool.self, forKey: .isStreaming)) ?? false
        imagePaths = try? c.decode([String].self, forKey: .imagePaths)
        let decodedAttachments = try? c.decode([ChatAttachment].self, forKey: .attachments)
        if let decodedAttachments, !decodedAttachments.isEmpty {
            attachments = decodedAttachments
        } else if let imagePaths, !imagePaths.isEmpty {
            attachments = imagePaths.map { path in
                ChatAttachment(
                    kind: .image,
                    originalName: URL(fileURLWithPath: path).lastPathComponent,
                    mimeType: nil,
                    localPath: path
                )
            }
        } else {
            attachments = nil
        }
        planAttachment = try? c.decode(PlanAttachment.self, forKey: .planAttachment)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(role, forKey: .role)
        try c.encode(content, forKey: .content)
        try c.encode(isStreaming, forKey: .isStreaming)
        try c.encodeIfPresent(planAttachment, forKey: .planAttachment)
        try c.encodeIfPresent(attachments, forKey: .attachments)
        let legacyImagePaths = imagePaths ?? attachments?
            .filter { $0.kind == .image }
            .map(\.localPath)
        try c.encodeIfPresent(legacyImagePaths, forKey: .imagePaths)
    }
}

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var contextId: UUID?
    var contextFolderPath: String?
    var mode: CoderMode?
    var preferredProviderId: String?
    var isArchived: Bool
    var isPinned: Bool
    var isFavorite: Bool

    // Legacy fields kept for one release migration path.
    var workspaceId: UUID?
    var adHocFolderPaths: [String]
    var checkpoints: [ConversationCheckpoint]

    init(
        id: UUID = UUID(),
        title: String = "New conversation",
        messages: [ChatMessage] = [],
        createdAt: Date = .now,
        contextId: UUID? = nil,
        contextFolderPath: String? = nil,
        mode: CoderMode? = nil,
        preferredProviderId: String? = nil,
        isArchived: Bool = false,
        isPinned: Bool = false,
        isFavorite: Bool = false,
        workspaceId: UUID? = nil,
        adHocFolderPaths: [String] = [],
        checkpoints: [ConversationCheckpoint] = []
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.contextId = contextId
        self.contextFolderPath = contextFolderPath
        self.mode = mode
        self.preferredProviderId = preferredProviderId
        self.isArchived = isArchived
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.workspaceId = workspaceId
        self.adHocFolderPaths = adHocFolderPaths
        self.checkpoints = checkpoints
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, messages, createdAt, contextId, contextFolderPath, mode, preferredProviderId, isArchived, isPinned, isFavorite, workspaceId, adHocFolderPaths, checkpoints
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
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
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(messages, forKey: .messages)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(contextId, forKey: .contextId)
        try c.encode(contextFolderPath, forKey: .contextFolderPath)
        try c.encode(mode?.rawValue, forKey: .mode)
        try c.encodeIfPresent(preferredProviderId, forKey: .preferredProviderId)
        try c.encode(isArchived, forKey: .isArchived)
        try c.encode(isPinned, forKey: .isPinned)
        try c.encode(isFavorite, forKey: .isFavorite)

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
    let gitStates: [ConversationCheckpointGitState]

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        messageCount: Int,
        planBoardSnapshot: PlanBoard?,
        gitStates: [ConversationCheckpointGitState]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.messageCount = messageCount
        self.planBoardSnapshot = planBoardSnapshot
        self.gitStates = gitStates
    }
}

private let conversationsStorageKey = "CoderIDE.conversations"
private let planBoardsStorageKey = "CoderIDE.planBoards"

private struct SendableUserDefaults: @unchecked Sendable {
    let value: UserDefaults
}

@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var activeTaskConversationIds: Set<UUID> = []
    @Published var taskStartDates: [UUID: Date] = [:]
    @Published private(set) var planBoards: [UUID: PlanBoard] = [:]
    private let userDefaults: UserDefaults

    /// Debounce task for coalescing rapid `saveConversations()` calls.
    private var pendingSaveTask: Task<Void, Never>?
    /// Debounce task for coalescing rapid `savePlanBoards()` calls.
    private var pendingPlanSaveTask: Task<Void, Never>?
    /// Background queue for serialization + UserDefaults writes.
    private static let persistQueue = DispatchQueue(label: "com.codigo.chatstore.persist", qos: .utility)

    /// True when any conversation has an active task.
    var isLoading: Bool { !activeTaskConversationIds.isEmpty }

    /// Convenience for callers that only need the single-active-task ID.
    var activeTaskConversationId: UUID? { activeTaskConversationIds.first }

    /// Per-conversation convenience (legacy compat).
    var taskStartDate: Date? {
        guard let first = activeTaskConversationIds.first else { return nil }
        return taskStartDates[first]
    }

    /// Check whether a specific conversation has an active task.
    func isTaskActive(for conversationId: UUID?) -> Bool {
        guard let id = conversationId else { return false }
        return activeTaskConversationIds.contains(id)
    }

    /// Start date for a specific conversation's active task.
    func taskStartDate(for conversationId: UUID?) -> Date? {
        guard let id = conversationId else { return nil }
        return taskStartDates[id]
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadConversations()
        loadPlanBoards()
        if conversations.isEmpty {
            createConversation(contextId: nil, contextFolderPath: nil, mode: nil)
        }
    }

    /// Threshold above which conversation loading happens on a background queue.
    private static let asyncLoadThreshold = 100_000 // 100 KB

    private func loadConversations() {
        guard let data = userDefaults.data(forKey: conversationsStorageKey) else { return }

        if data.count < Self.asyncLoadThreshold {
            // Small dataset – decode synchronously (fast enough, avoids empty-flash).
            if let decoded = try? JSONDecoder().decode([Conversation].self, from: data) {
                conversations = decoded
            }
            return
        }

        // Large dataset – decode on a background queue to avoid blocking the main thread.
        Task.detached(priority: .userInitiated) {
            guard let decoded = try? JSONDecoder().decode([Conversation].self, from: data) else { return }
            await MainActor.run {
                if self.conversations.isEmpty || self.conversations.first?.messages.isEmpty == true {
                    self.conversations = decoded
                } else if !decoded.isEmpty {
                    let existingIds = Set(self.conversations.map(\.id))
                    let loaded = decoded.filter { !existingIds.contains($0.id) }
                    self.conversations = loaded + self.conversations
                }
            }
        }
    }

    func saveConversations() {
        pendingSaveTask?.cancel()
        let snapshot = conversations
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            let defaults = SendableUserDefaults(value: self.userDefaults)
            Self.persistQueue.async {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                defaults.value.set(data, forKey: conversationsStorageKey)
            }
        }
    }

    private func loadPlanBoards() {
        guard let data = userDefaults.data(forKey: planBoardsStorageKey) else { return }

        let decode: () -> [UUID: PlanBoard]? = {
            guard let decoded = try? JSONDecoder().decode([String: PlanBoard].self, from: data) else { return nil }
            return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value -> (UUID, PlanBoard)? in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value)
            })
        }

        if data.count < Self.asyncLoadThreshold {
            if let boards = decode() { planBoards = boards }
            return
        }

        Task.detached(priority: .userInitiated) {
            guard let boards = decode() else { return }
            await MainActor.run {
                self.planBoards.merge(boards) { _, loaded in loaded }
            }
        }
    }

    private func savePlanBoards() {
        pendingPlanSaveTask?.cancel()
        let snapshot = planBoards
        pendingPlanSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            let serialized = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.key.uuidString, $0.value) })
            let defaults = SendableUserDefaults(value: self.userDefaults)
            Self.persistQueue.async {
                guard let data = try? JSONEncoder().encode(serialized) else { return }
                defaults.value.set(data, forKey: planBoardsStorageKey)
            }
        }
    }

    func migrateLegacyContextsIfNeeded(contextStore: ProjectContextStore, workspaceStore: WorkspaceStore) {
        contextStore.ensureWorkspaceContexts(workspaceStore.workspaces)
        var changed = false
        for idx in conversations.indices {
            if conversations[idx].contextId == nil {
                if let workspaceId = conversations[idx].workspaceId {
                    conversations[idx].contextId = workspaceId
                    changed = true
                } else if !conversations[idx].adHocFolderPaths.isEmpty,
                          let contextId = contextStore.createOrReuseSingleProject(paths: conversations[idx].adHocFolderPaths) {
                    conversations[idx].contextId = contextId
                    changed = true
                }
            }
        }
        if changed { saveConversations() }
    }

    @discardableResult
    func createConversation(contextId: UUID? = nil, contextFolderPath: String? = nil, mode: CoderMode? = nil) -> UUID {
        let conv = Conversation(contextId: contextId, contextFolderPath: contextFolderPath, mode: mode)
        conversations.append(conv)
        saveConversations()
        return conv.id
    }

    // Legacy wrappers for callers still using old API.
    @discardableResult
    func createConversation(workspaceId: UUID? = nil, adHocFolderPaths: [String] = [], mode: CoderMode? = nil) -> UUID {
        let conv = Conversation(contextId: workspaceId, mode: mode, workspaceId: workspaceId, adHocFolderPaths: adHocFolderPaths)
        conversations.append(conv)
        saveConversations()
        return conv.id
    }

    func conversationForMode(contextId: UUID?, contextFolderPath: String? = nil, mode: CoderMode) -> Conversation? {
        conversations.first { conv in
            conv.contextId == contextId && conv.mode == mode && (contextFolderPath == nil || conv.contextFolderPath == contextFolderPath)
        }
    }

    @discardableResult
    func getOrCreateConversationForMode(contextId: UUID?, contextFolderPath: String? = nil, mode: CoderMode) -> UUID {
        if let existing = conversationForMode(contextId: contextId, contextFolderPath: contextFolderPath, mode: mode) {
            return existing.id
        }
        return createConversation(contextId: contextId, contextFolderPath: contextFolderPath, mode: mode)
    }

    // Legacy wrappers for old callers.
    func conversationForMode(workspaceId: UUID?, mode: CoderMode, adHocFolderPaths: [String] = []) -> Conversation? {
        conversations.first { conv in
            conv.contextId == workspaceId && conv.mode == mode && (adHocFolderPaths.isEmpty || Set(conv.adHocFolderPaths) == Set(adHocFolderPaths))
        }
    }

    @discardableResult
    func getOrCreateConversationForMode(workspaceId: UUID?, mode: CoderMode, adHocFolderPaths: [String] = []) -> UUID {
        if let existing = conversationForMode(workspaceId: workspaceId, mode: mode, adHocFolderPaths: adHocFolderPaths) {
            return existing.id
        }
        return createConversation(workspaceId: workspaceId, adHocFolderPaths: adHocFolderPaths, mode: mode)
    }

    func deleteConversation(id: UUID) {
        conversations.removeAll { $0.id == id }
        planBoards.removeValue(forKey: id)
        if conversations.isEmpty { createConversation(contextId: nil, contextFolderPath: nil, mode: nil) }
        saveConversations()
        savePlanBoards()
    }

    func setPinned(conversationId: UUID, pinned: Bool) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].isPinned = pinned
        saveConversations()
    }

    func setFavorite(conversationId: UUID, favorite: Bool) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].isFavorite = favorite
        saveConversations()
    }

    func setArchived(conversationId: UUID, archived: Bool) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].isArchived = archived
        saveConversations()
    }

    func setTitle(conversationId: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].title = trimmed
        saveConversations()
    }

    func updatePreferredProvider(conversationId: UUID?, providerId: String?) {
        guard let id = conversationId,
              let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].preferredProviderId = providerId?.isEmpty == true ? nil : providerId
        saveConversations()
    }

    func searchThreads(query: String, includeArchived: Bool = true, limit: Int = 50) -> [ThreadSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [ThreadSearchHit] = []

        for conv in conversations {
            if !includeArchived, conv.isArchived { continue }
            var score = 0
            var snippet = conv.title
            let titleLower = conv.title.lowercased()
            if titleLower.contains(q) { score += 2 }

            let assistantAndUser = conv.messages.map(\.content).joined(separator: "\n")
            let bodyLower = assistantAndUser.lowercased()
            if bodyLower.contains(q) {
                score += 1
                if let range = bodyLower.range(of: q) {
                    let idx = bodyLower.distance(from: bodyLower.startIndex, to: range.lowerBound)
                    let start = max(0, idx - 60)
                    let end = min(bodyLower.count, idx + 140)
                    let sIdx = assistantAndUser.index(assistantAndUser.startIndex, offsetBy: start)
                    let eIdx = assistantAndUser.index(assistantAndUser.startIndex, offsetBy: end)
                    snippet = String(assistantAndUser[sIdx..<eIdx]).replacingOccurrences(of: "\n", with: " ")
                }
            }

            guard score > 0 else { continue }
            let count = titleLower.components(separatedBy: q).count - 1 + bodyLower.components(separatedBy: q).count - 1
            hits.append(ThreadSearchHit(
                id: conv.id,
                conversationId: conv.id,
                title: conv.title,
                snippet: snippet,
                matchCount: max(1, count),
                isArchived: conv.isArchived,
                isFavorite: conv.isFavorite
            ))
        }

        return hits.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
            if $0.matchCount != $1.matchCount { return $0.matchCount > $1.matchCount }
            return $0.title < $1.title
        }.prefix(limit).map { $0 }
    }

    func buildThreadSearchAIPrompt(query: String, hits: [ThreadSearchHit], maxItems: Int = 12) -> String {
        let items = hits.prefix(maxItems).map {
            "- Thread: \($0.title)\n  Match: \($0.matchCount)\n  Snippet: \($0.snippet)"
        }.joined(separator: "\n")
        return """
        Use exclusively the context of the threads found below to answer my question.
        If the context is not enough, state it clearly.

        Search query: \(query)

        Thread results:
        \(items)

        Question:
        """
    }

    func clearWorkspaceReferences(workspaceId: UUID) {
        for i in conversations.indices where conversations[i].contextId == workspaceId || conversations[i].workspaceId == workspaceId {
            conversations[i].contextId = nil
            conversations[i].workspaceId = nil
            conversations[i].adHocFolderPaths = []
        }
        saveConversations()
    }

    func setContext(conversationId: UUID?, contextId: UUID?) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].contextId = contextId
        conversations[idx].contextFolderPath = nil
        conversations[idx].workspaceId = contextId
        conversations[idx].adHocFolderPaths = []
        saveConversations()
    }

    func setContextFolder(conversationId: UUID?, folderPath: String?) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].contextFolderPath = folderPath
        saveConversations()
    }

    func setWorkspace(conversationId: UUID?, workspaceId: UUID?) {
        setContext(conversationId: conversationId, contextId: workspaceId)
    }

    func setAdHocPaths(conversationId: UUID?, paths: [String]) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].contextId = nil
        conversations[idx].contextFolderPath = nil
        conversations[idx].workspaceId = nil
        conversations[idx].adHocFolderPaths = paths
        saveConversations()
    }

    func conversation(for id: UUID?) -> Conversation? {
        guard let id else { return nil }
        return conversations.first { $0.id == id }
    }

    func exportConversationMarkdown(conversationId: UUID?) -> String? {
        guard let conversation = conversation(for: conversationId) else { return nil }

        let title = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty ? "Chat" : title
        let formatter = ISO8601DateFormatter()

        var lines: [String] = []
        lines.append("# \(resolvedTitle)")
        lines.append("Exported: \(formatter.string(from: Date()))")
        lines.append("")

        for message in conversation.messages {
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let nonImageAttachments = (message.attachments ?? []).filter { $0.kind != .image }
            if content.isEmpty, nonImageAttachments.isEmpty { continue }

            lines.append("## \(message.role == .user ? "You" : "Assistant")")
            if !content.isEmpty {
                lines.append(content)
            }

            if !nonImageAttachments.isEmpty {
                if !content.isEmpty {
                    lines.append("")
                }
                lines.append("Attachments:")
                for attachment in nonImageAttachments {
                    lines.append("- \(attachment.originalName)")
                }
            }

            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    func defaultMarkdownFilename(for conversationId: UUID?) -> String {
        let rawTitle = conversation(for: conversationId)?.title ?? ""
        let sanitized = Self.sanitizeFilenameComponent(rawTitle)
        return "\(sanitized).md"
    }

    @discardableResult
    func forkConversation(from conversationId: UUID?) -> UUID? {
        guard let source = conversation(for: conversationId) else { return nil }

        let baseTitle = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseTitle = baseTitle.isEmpty ? "Chat" : baseTitle

        let forkedMessages = source.messages.map { message in
            ChatMessage(
                id: UUID(),
                role: message.role,
                content: message.content,
                isStreaming: false,
                imagePaths: message.imagePaths,
                attachments: message.attachments,
                planAttachment: nil
            )
        }

        let forkedConversation = Conversation(
            title: "\(resolvedBaseTitle) (Fork)",
            messages: forkedMessages,
            createdAt: .now,
            contextId: source.contextId,
            contextFolderPath: source.contextFolderPath,
            mode: source.mode,
            preferredProviderId: source.preferredProviderId,
            isArchived: false,
            isPinned: false,
            isFavorite: false,
            workspaceId: source.workspaceId,
            adHocFolderPaths: source.adHocFolderPaths,
            checkpoints: []
        )

        conversations.append(forkedConversation)
        saveConversations()
        return forkedConversation.id
    }

    func isAssistantStreaming(in conversationId: UUID?) -> Bool {
        guard let conversation = conversation(for: conversationId) else { return false }
        guard let lastAssistant = conversation.messages.last(where: { $0.role == .assistant }) else {
            return false
        }
        return lastAssistant.isStreaming
    }

    private static func sanitizeFilenameComponent(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "chat" }

        value = value.replacingOccurrences(
            of: #"[\\/:*?"<>|]"#,
            with: "-",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(of: " ", with: "_")
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        if value.isEmpty { return "chat" }
        return String(value.prefix(80))
    }

    /// Sets isStreaming=false on all assistant messages. Call before adding
    /// a new assistant placeholder to avoid duplicate loading indicators.
    func clearStaleAssistantStreaming(conversationId: UUID?) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        var conv = conversations[idx]
        var msgs = conv.messages
        var changed = false
        for i in msgs.indices where msgs[i].role == .assistant {
            if msgs[i].isStreaming {
                msgs[i].isStreaming = false
                changed = true
            }
        }
        if changed {
            conv.messages = msgs
            conversations[idx] = conv
            saveConversations()
        }
    }

    func addMessage(_ message: ChatMessage, to conversationId: UUID?) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        if message.role == .assistant, message.isStreaming {
            clearStaleAssistantStreaming(conversationId: conversationId)
        }
        conversations[idx].messages.append(message)
        if conversations[idx].title == "New conversation", case .user = message.role {
            conversations[idx].title = String(message.content.prefix(40))
            if message.content.count > 40 { conversations[idx].title += "…" }
        }
        saveConversations()
    }

    /// - Parameter persistImmediately: if false, skips saveConversations (use during streaming to avoid blocking the main thread with I/O).
    func updateLastAssistantMessage(content: String, in conversationId: UUID?, persistImmediately: Bool = true) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        guard let lastIdx = conversations[idx].messages.lastIndex(where: { $0.role == .assistant }) else { return }
        // During streaming use a conservative sanitization:
        // avoid removing legitimate "operational" phrases that otherwise make
        // the text appear stuck after the first chunk.
        let stripped = Self.stripCoderideMarkers(content, aggressive: persistImmediately)
        let rawTrimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedContent: String
        if stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !rawTrimmed.isEmpty {
            // Defensive fallback: never lose assistant content on non-Codex providers.
            // If aggressive sanitization empties everything, retry in conservative mode.
            let conservative = Self.stripCoderideMarkers(content, aggressive: false)
            resolvedContent = conservative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? content
                : conservative
        } else {
            resolvedContent = stripped
        }
        // Mutate in-place to avoid creating intermediate array copies on every streaming token.
        conversations[idx].messages[lastIdx].content = resolvedContent
        if persistImmediately { saveConversations() }
    }

    func removeAssistantMessageIfEmpty(messageId: UUID, in conversationId: UUID?) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        guard let midx = conversations[idx].messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        let message = conversations[idx].messages[midx]
        guard message.role == .assistant else { return }
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return }
        conversations[idx].messages.remove(at: midx)
        saveConversations()
    }

    // MARK: - Cached regex patterns (compiled once, reused on every call)

    private enum MarkerRegex {
        static let coderideMarker = try! NSRegularExpression(
            pattern: "\\[\\s*CODERIDE\\s*:[^\\]\\n]*\\]", options: .caseInsensitive)
        static let ideFilesLine = try! NSRegularExpression(
            pattern: #"^[^\n]*IDE\s*:\s*files\s*=[^\]\n]*\]?\s*"#,
            options: [.caseInsensitive, .anchorsMatchLines])
        static let opLineIDE = try! NSRegularExpression(
            pattern: #"^(?:Creating|Generating|Processing|Analyzing|Reading|Writing|Updating)\s+[^\n]*?(?:IDE|CODERIDE|planIDE)[^\n]*$"#,
            options: [.caseInsensitive, .anchorsMatchLines])
        static let bugReview = try! NSRegularExpression(
            pattern: #"(?im)^Planning\s+(?:bug\s+review|code\s+review)\s+workflow\s*$"#,
            options: [.caseInsensitive, .anchorsMatchLines])
        static let inlineOpPrefix = try! NSRegularExpression(
            pattern: #"(?im)^(\s*(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing|Inspecting)\s+(?:initial\s+)?(?:task\s+panel(?:\s+and\s+todo\s+update)?|todo(?:\s+update)?|workflow(?:\s+steps?)?|project\s+analysis|analysis|plan|execution(?:\s+flow)?)(?:\s+and\s+todo\s+update)?\s+)"#,
            options: [.caseInsensitive, .anchorsMatchLines])
        static let initBoilerplate = try! NSRegularExpression(
            pattern: #"(?im)^(?:(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing)\s+(?:initial\s+)?(?:task\s+panel|todo|workflow|workflow\s+steps?|project\s+analysis|analysis|plan|execution|execution\s+flow|operations?)\b[^\n]*|(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing)\s+[^\n]*(?:task\s+panel|todo|workflow|analysis|plan|execution)\b[^\n]*)$"#,
            options: [.caseInsensitive, .anchorsMatchLines])
        static let progressHeading = try! NSRegularExpression(
            pattern: #"(?im)^(?:\*{1,2}\s*)?(?:Updating|Planning|Reading|Analyzing|Implementing)\b[^\n]{0,140}(?:\*{1,2})?\s*$"#,
            options: [.caseInsensitive, .anchorsMatchLines])
        static let cliTrace = try! NSRegularExpression(
            pattern: #"(?im)^(?:Explored\s+\d+\s+files?(?:,\s*\d+\s+search(?:es)?)?(?:,\s*\d+\s+list)?|Ran\s+[^\n]+|Inspecting\s+[^\n]+)\s*$"#,
            options: [.caseInsensitive, .anchorsMatchLines])
        static let inlineMarkerPrefix = try! NSRegularExpression(
            pattern: #"(?i)\bmarkers\s*:\s*[a-z_][a-z0-9_]*\|"#, options: [])
        static let inlineMarkerTypes = try! NSRegularExpression(
            pattern: #"(?i)\b(?:todo_write|todo_read|plan_step(?:_update)?|read_batch(?:_started|_completed)?|web_search(?:_started|_completed|_failed)?|web_fetch(?:_started|_completed|_failed)?|instant_grep)\|"#, options: [])
        static let inlineMarkerBroken = try! NSRegularExpression(
            pattern: #"(?i)\b(?:markers)?[a-z_]*(?:todo_write|todo_read|do_write|do_read|plan_step(?:_update)?|read_batch(?:_started|_completed)?|web_search(?:_started|_completed|_failed)?|web_fetch(?:_started|_completed|_failed)?|instant_grep)\|"#, options: [])
        static let technicalEvents = try! NSRegularExpression(
            pattern: #"(?i)\b(?:coderide_show_task_panel|coderide_invoke_swarm|read_batch_started|read_batch_completed|web_search_started|web_search_completed|web_search_failed|web_fetch_started|web_fetch_completed|web_fetch_failed|plan_step(?:_update)?|todo_write|todo_read|instant_grep)\b"#, options: [])
        static let stickyKeyValue = try! NSRegularExpression(
            pattern: #"([A-Za-zÀ-ÖØ-öø-ÿ])((?i:files|count|group_id|queryid|query|step_id|pathscope|matchescount|previewlines|status|priority|notes|title|id|task)=)"#, options: [])
        static let singleKeyValue = try! NSRegularExpression(
            pattern: #"(?i)\b(?:id|title|status|priority|notes|files|step_id|queryid|query|group_id|count|task)=[^|\n\r]+(?:\||$)"#, options: [])
        static let keyValueBracket = try! NSRegularExpression(
            pattern: #"(?i)\b(?:id|title|status|priority|notes|files|step_id|queryid|query|group_id|count|task|pathscope|matchescount|previewlines)=[^\]\n\r]+\]"#, options: [])
        static let trailingSpaceNewline = try! NSRegularExpression(pattern: #"\s+\n"#, options: [])
        static let excessiveNewlines = try! NSRegularExpression(pattern: #"\n{3,}"#, options: [])
        static let excessiveSpaces = try! NSRegularExpression(pattern: #"[ \t]{2,}"#, options: [])
        static let missingSpaceAfterPunct = try! NSRegularExpression(
            pattern: #"([.!?])([A-Za-zÀ-ÖØ-öø-ÿ])"#, options: [])
        static let tripleNewlines = try! NSRegularExpression(pattern: #"\n\n\n+"#, options: [])
        static let structuredPayload = try! NSRegularExpression(
            pattern: #"(?i)(?:\b[a-z_][a-z0-9_]*=[^|\n\r]+(?:\|\s*|\s*$)){2,}"#, options: [])
    }

    /// Helper: apply pre-compiled NSRegularExpression as a replacement on the full string.
    private static func applyRegex(_ regex: NSRegularExpression, on string: inout String, template: String) {
        let ns = string as NSString
        string = regex.stringByReplacingMatches(
            in: string, range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }

    /// Removes CODERIDE markers from source to avoid flashes during streaming.
    static func stripCoderideMarkers(_ content: String, aggressive: Bool = true) -> String {
        var out = content
        // 1. Standard [CODERIDE:...] markers
        while true {
            let ns = out as NSString
            guard let match = MarkerRegex.coderideMarker.firstMatch(
                in: out, range: NSRange(location: 0, length: ns.length)) else { break }
            let start = out.index(out.startIndex, offsetBy: match.range.location)
            let end = out.index(start, offsetBy: match.range.length)
            out.removeSubrange(start..<end)
        }
        // 2. Fallback for incomplete [CODERIDE markers
        while let start = out.range(of: "[CODERIDE", options: .caseInsensitive) {
            if let end = out[start.upperBound...].firstIndex(of: "]") {
                out.removeSubrange(start.lowerBound..<out.index(after: end))
            } else {
                if let newline = out[start.lowerBound...].firstIndex(of: "\n") {
                    out.removeSubrange(start.lowerBound..<newline)
                } else {
                    out.removeSubrange(start.lowerBound..<out.endIndex)
                }
                break
            }
        }
        if aggressive {
            applyRegex(MarkerRegex.ideFilesLine, on: &out, template: "")
            applyRegex(MarkerRegex.opLineIDE, on: &out, template: "")
            applyRegex(MarkerRegex.bugReview, on: &out, template: "")
            applyRegex(MarkerRegex.inlineOpPrefix, on: &out, template: "")
            applyRegex(MarkerRegex.initBoilerplate, on: &out, template: "")
            applyRegex(MarkerRegex.progressHeading, on: &out, template: "")
            applyRegex(MarkerRegex.cliTrace, on: &out, template: "")
        }
        // Inline markers
        applyRegex(MarkerRegex.inlineMarkerPrefix, on: &out, template: "")
        applyRegex(MarkerRegex.inlineMarkerTypes, on: &out, template: "")
        applyRegex(MarkerRegex.inlineMarkerBroken, on: &out, template: "")
        applyRegex(MarkerRegex.technicalEvents, on: &out, template: "")
        if aggressive {
            applyRegex(MarkerRegex.stickyKeyValue, on: &out, template: "$1 $2")
            applyRegex(MarkerRegex.singleKeyValue, on: &out, template: "")
            applyRegex(MarkerRegex.keyValueBracket, on: &out, template: "")
            out = stripStructuredMarkerPayloads(out)
        }
        // Cleanup formatting
        applyRegex(MarkerRegex.trailingSpaceNewline, on: &out, template: "\n")
        applyRegex(MarkerRegex.excessiveNewlines, on: &out, template: "\n\n")
        applyRegex(MarkerRegex.excessiveSpaces, on: &out, template: " ")
        applyRegex(MarkerRegex.missingSpaceAfterPunct, on: &out, template: "$1 $2")
        applyRegex(MarkerRegex.tripleNewlines, on: &out, template: "\n\n")
        return aggressive ? out.trimmingCharacters(in: .whitespacesAndNewlines) : out
    }

    private static let structuredPayloadMarkerKeys: Set<String> = [
        "id", "title", "status", "priority", "notes", "files", "step_id",
        "queryid", "query", "group_id", "count", "task",
    ]

    private static func stripStructuredMarkerPayloads(_ input: String) -> String {
        let regex = MarkerRegex.structuredPayload
        var out = input
        while true {
            let ns = out as NSString
            let range = NSRange(location: 0, length: ns.length)
            let matches = regex.matches(in: out, options: [], range: range)
            guard !matches.isEmpty else { break }
            var removed = false
            for match in matches.reversed() {
                guard let strRange = Range(match.range, in: out) else { continue }
                let chunk = String(out[strRange])
                let keys = chunk
                    .split(separator: "|")
                    .compactMap { segment -> String? in
                        guard let eq = segment.firstIndex(of: "=") else { return nil }
                        return String(segment[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                    }
                guard !keys.isEmpty else { continue }
                let markerKeyCount = keys.filter { structuredPayloadMarkerKeys.contains($0) }.count
                if markerKeyCount >= 3 {
                    out.removeSubrange(strRange)
                    removed = true
                }
            }
            if !removed { break }
        }
        return out
    }

    /// Extracts the last "operational" line from content during streaming (e.g. "Planning next moves", "Explored lints").
    /// Used to show LLM thinking like Cursor does.
    static func extractLastOperationalThinkingLine(from content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lines = trimmed.components(separatedBy: .newlines)
        let operationalPrefixes = [
            "Planning", "Explored", "Inspecting", "Ran ", "Reading", "Analyzing",
            "Implementing", "Updating", "Creating", "Generating", "Processing",
            "Setting", "Preparing", "Starting", "Initializing", "Bootstrapping",
            "Writing", "Searching"
        ]
        for line in lines.reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.count > 3, t.count < 150 else { continue }
            let lower = t.lowercased()
            for prefix in operationalPrefixes {
                if lower.hasPrefix(prefix.lowercased()) {
                    return t
                }
            }
        }
        return nil
    }

    func setLastAssistantStreaming(_ streaming: Bool, in conversationId: UUID?) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        guard let lastIdx = conversations[idx].messages.lastIndex(where: { $0.role == .assistant }) else { return }
        var conv = conversations[idx]
        var msgs = conv.messages
        var msg = msgs[lastIdx]
        msg.isStreaming = streaming
        msgs[lastIdx] = msg
        conv.messages = msgs
        var updated = conversations
        updated[idx] = conv
        conversations = updated
        saveConversations()
    }

    func beginTask(conversationId: UUID?) {
        guard let id = conversationId else { return }
        activeTaskConversationIds.insert(id)
        taskStartDates[id] = Date()
    }

    // Legacy call site compatibility.
    func beginTask() {
        beginTask(conversationId: activeTaskConversationId)
    }

    func endTask(conversationId: UUID?) {
        guard let id = conversationId else { return }
        activeTaskConversationIds.remove(id)
        taskStartDates.removeValue(forKey: id)
    }

    // Compat legacy call sites.
    func endTask() {
        endTask(conversationId: activeTaskConversationId)
    }

    func setPlanBoard(_ board: PlanBoard, for conversationId: UUID?) {
        guard let conversationId else { return }
        planBoards[conversationId] = board
        savePlanBoards()
    }

    func choosePlanPath(_ chosenPath: String, for conversationId: UUID?) {
        guard let conversationId, var board = planBoards[conversationId] else { return }
        board.chosenPath = chosenPath
        let optionTodos = PlanOptionsParser.extractTodosFromOptionText(chosenPath)
        board.steps = PlanBoard.buildSteps(fromTodoTitles: optionTodos)
        board.updatedAt = .now
        planBoards[conversationId] = board
        savePlanBoards()
    }

    func planBoard(for conversationId: UUID?) -> PlanBoard? {
        guard let conversationId else { return nil }
        return planBoards[conversationId]
    }

    func attachPlanEntry(
        toMessageId messageId: UUID,
        conversationId: UUID?,
        entry: PlanHistoryEntry
    ) {
        guard let cidx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        guard let midx = conversations[cidx].messages.firstIndex(where: { $0.id == messageId }) else { return }
        conversations[cidx].messages[midx].planAttachment = PlanAttachment(
            historyEntryId: entry.id,
            layoutVersion: 1,
            showExpand: true,
            snapshotTitle: entry.title
        )
        saveConversations()
    }

    @discardableResult
    func attachPlanEntryToLastAssistant(
        conversationId: UUID?,
        entry: PlanHistoryEntry
    ) -> UUID? {
        guard let cidx = conversations.firstIndex(where: { $0.id == conversationId }) else { return nil }
        guard let midx = conversations[cidx].messages.lastIndex(where: { $0.role == .assistant }) else {
            return nil
        }
        let msgId = conversations[cidx].messages[midx].id
        conversations[cidx].messages[midx].planAttachment = PlanAttachment(
            historyEntryId: entry.id,
            layoutVersion: 1,
            showExpand: true,
            snapshotTitle: entry.title
        )
        saveConversations()
        return msgId
    }

    func backfillPlanAttachmentsIfNeeded(historyStore: PlanHistoryStore) {
        var changed = false
        for cidx in conversations.indices {
            let conv = conversations[cidx]
            for midx in conversations[cidx].messages.indices {
                var msg = conversations[cidx].messages[midx]
                guard msg.role == .assistant else { continue }
                if msg.planAttachment != nil { continue }
                let opts = PlanOptionsParser.parseStrict(from: msg.content)
                guard !opts.isEmpty else { continue }
                let normalizedHash = normalizedPlanContentHash(msg.content)
                let summary = PlanOptionsParser.extractDisplaySummary(from: msg.content)
                let existing = historyStore.findEntry(
                    conversationId: conv.id,
                    sourceMessageId: msg.id
                )
                let existingByHash = historyStore.entries.first(where: { entry in
                    guard entry.conversationId == conv.id else { return false }
                    guard entry.sourceMessageId == msg.id else { return false }
                    return normalizedPlanContentHash(entry.markdown) == normalizedHash
                })
                let entry: PlanHistoryEntry
                if let existingByHash {
                    entry = existingByHash
                } else if let existing {
                    entry = existing
                } else {
                    entry = historyStore.createEntry(
                        conversationId: conv.id,
                        contextId: conv.contextId,
                        contextFolderPath: conv.contextFolderPath,
                        title: summary.title,
                        markdown: msg.content,
                        options: opts,
                        chosenPath: nil,
                        tags: [],
                        sourceMessageId: msg.id
                    )
                }
                msg.planAttachment = PlanAttachment(
                    historyEntryId: entry.id,
                    layoutVersion: 1,
                    showExpand: true,
                    snapshotTitle: entry.title
                )
                conversations[cidx].messages[midx] = msg
                changed = true
            }
        }
        if changed {
            saveConversations()
        }
    }

    private func normalizedPlanContentHash(_ raw: String) -> Int {
        let normalized = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .lowercased()
        return normalized.hashValue
    }

    func updatePlanStepStatus(stepId: String, status: PlanStepStatus, in conversationId: UUID?) {
        guard let conversationId, var board = planBoards[conversationId] else { return }
        guard let index = board.steps.firstIndex(where: { $0.id == stepId }) else { return }
        board.steps[index].status = status
        board.updatedAt = .now
        planBoards[conversationId] = board
        savePlanBoards()
    }

    func syncPlanStepsFromCanonicalTodos(_ todos: [TodoItem], in conversationId: UUID?) {
        guard let conversationId else { return }
        var board = planBoards[conversationId] ?? PlanBoard(
            goal: "Operational plan in progress",
            options: [],
            chosenPath: nil,
            steps: [],
            updatedAt: .now,
            walkthroughMarkdown: nil
        )

        let canonicalTodos = todos
            .filter(\.isPlanCanonical)
            .sorted(by: { $0.createdAt < $1.createdAt })

        let steps = PlanBoard.buildSteps(
            fromTodoTitles: canonicalTodos.map(\.title),
            statusForIndex: { index in
                guard canonicalTodos.indices.contains(index) else { return .pending }
                switch canonicalTodos[index].status {
                case .pending:
                    return .pending
                case .inProgress:
                    return .running
                case .done:
                    return .done
                case .blocked:
                    return .failed
                }
            }
        )

        board.steps = steps
        board.updatedAt = .now
        planBoards[conversationId] = board
        savePlanBoards()
    }

    func upsertPlanStep(
        stepId: String,
        status: PlanStepStatus,
        title: String? = nil,
        in conversationId: UUID?
    ) {
        guard let conversationId else { return }
        var board = planBoards[conversationId] ?? PlanBoard(
            goal: "Operational plan in progress",
            options: [],
            chosenPath: nil,
            steps: [],
            updatedAt: .now,
            walkthroughMarkdown: nil
        )

        if let index = board.steps.firstIndex(where: { $0.id == stepId }) {
            board.steps[index].status = status
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                board.steps[index].title = title
                board.steps[index].description = title
            }
        } else {
            let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = (cleanTitle?.isEmpty == false) ? cleanTitle! : "Step \(stepId)"
            board.steps.append(
                PlanStep(
                    id: stepId,
                    title: resolvedTitle,
                    description: resolvedTitle,
                    targetFile: nil,
                    status: status
                )
            )
        }

        board.updatedAt = .now
        planBoards[conversationId] = board
        savePlanBoards()
    }

    func setWalkthrough(_ markdown: String, for conversationId: UUID?) {
        guard let conversationId, var board = planBoards[conversationId] else { return }
        board.walkthroughMarkdown = markdown
        board.updatedAt = .now
        planBoards[conversationId] = board
        savePlanBoards()
    }

    func summarizeConversation(
        id: UUID?,
        keepLast: Int,
        provider: any CoderEngine.LLMProvider,
        context: CoderEngine.WorkspaceContext
    ) async throws -> Bool {
        guard let cid = id, let idx = conversations.firstIndex(where: { $0.id == cid }) else { return false }
        let msgs = conversations[idx].messages
        let safeKeepLast = max(2, keepLast)
        guard msgs.count > safeKeepLast + 2 else { return false }

        let toSummarize = Array(msgs.prefix(msgs.count - safeKeepLast))
        let recent = Array(msgs.suffix(safeKeepLast))
        let previousSummary = msgs.first(where: {
            $0.role == .assistant
                && ($0.content.contains("[Conversation summary]")
                    || $0.content.contains("[Previous summary]"))
        })

        let textToSummarize = toSummarize.map { message in
            let roleLabel = message.role == .user ? "User" : "Assistant"
            let cleaned = ChatStore.stripCoderideMarkers(message.content)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(roleLabel): \(cleaned)"
        }.joined(separator: "\n\n")

        let previousSummaryBlock: String = {
            guard let previousSummary else { return "" }
            let cleaned = ChatStore.stripCoderideMarkers(previousSummary.content)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return "" }
            return """
            Existing summary (update and preserve stable facts):
            \(cleaned)

            """
        }()

        let prompt = """
        Create an updated compact conversation memory for a coding assistant.

        Rules:
        - Preserve objectives, constraints, decisions, current status, unresolved issues.
        - Preserve user preferences (language/style/tooling), and important environment assumptions.
        - Preserve modified files and verification outcomes (tests/build).
        - Remove noise, repetition, and transient tool chatter.
        - Keep it concise but complete enough for high-quality follow-ups.
        - Output in English.
        - Output ONLY markdown with these sections in this exact order:
          1) ## Objectives
          2) ## Decisions
          3) ## Progress
          4) ## Open items
          5) ## User preferences

        \(previousSummaryBlock)Conversation to summarize:
        \(textToSummarize)
        """
        let ctx = CoderEngine.WorkspaceContext(
            workspacePaths: context.workspacePaths,
            isNamedWorkspace: false,
            workspaceName: nil,
            excludedPaths: [],
            openFiles: [],
            activeSelection: nil,
            activeFilePath: nil,
            activeRootPath: context.activeRootPath
        )
        let stream = try await provider.send(prompt: prompt, context: ctx, imageURLs: nil)
        var summary = ""
        for try await ev in stream {
            if case .textDelta(let d) = ev { summary += d }
            if case .error(let e) = ev { summary += "\n[Error: \(e)]" }
        }
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let summaryMsg = ChatMessage(
            role: .assistant,
            content: "[Conversation summary]\n\n\(summary.trimmingCharacters(in: .whitespacesAndNewlines))",
            isStreaming: false
        )
        conversations[idx].messages = [summaryMsg] + recent
        saveConversations()
        return true
    }

    func createCheckpoint(for conversationId: UUID?, gitStates: [ConversationCheckpointGitState]) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let checkpoint = ConversationCheckpoint(
            messageCount: conversations[idx].messages.count,
            planBoardSnapshot: planBoards[conversations[idx].id],
            gitStates: gitStates
        )
        conversations[idx].checkpoints.append(checkpoint)
        saveConversations()
    }

    func canRewind(conversationId: UUID?) -> Bool {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return false }
        return !conversations[idx].checkpoints.isEmpty
    }

    func previousCheckpoint(conversationId: UUID?) -> ConversationCheckpoint? {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return nil }
        return conversations[idx].checkpoints.last
    }

    func checkpoint(forMessageIndex messageIndex: Int, conversationId: UUID?) -> ConversationCheckpoint? {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return nil }
        return conversations[idx].checkpoints.last { $0.messageCount == (messageIndex + 1) }
    }

    @discardableResult
    func rewindConversationState(to checkpointId: UUID, conversationId: UUID?) -> Bool {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return false }
        guard let cpIdx = conversations[idx].checkpoints.lastIndex(where: { $0.id == checkpointId }) else { return false }
        let checkpoint = conversations[idx].checkpoints[cpIdx]
        guard checkpoint.messageCount <= conversations[idx].messages.count else { return false }

        conversations[idx].messages = Array(conversations[idx].messages.prefix(checkpoint.messageCount))
        if let snapshot = checkpoint.planBoardSnapshot {
            planBoards[conversations[idx].id] = snapshot
        } else {
            planBoards.removeValue(forKey: conversations[idx].id)
        }
        conversations[idx].checkpoints = Array(conversations[idx].checkpoints.prefix(cpIdx))
        saveConversations()
        savePlanBoards()
        return true
    }

    func trimFutureCheckpoints(conversationId: UUID?, maxMessageCount: Int) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].checkpoints.removeAll { $0.messageCount > maxMessageCount }
        saveConversations()
    }

    @discardableResult
    func rewindConversationToMessageCount(_ messageCount: Int, conversationId: UUID?) -> Bool {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return false }
        guard messageCount >= 0, messageCount <= conversations[idx].messages.count else { return false }
        conversations[idx].messages = Array(conversations[idx].messages.prefix(messageCount))
        conversations[idx].checkpoints.removeAll { $0.messageCount > messageCount }
        saveConversations()
        return true
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
