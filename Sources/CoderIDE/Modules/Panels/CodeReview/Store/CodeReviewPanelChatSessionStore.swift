import Foundation

@MainActor
final class ReviewPanelChatSessionStore: ObservableObject {
    static let shared = ReviewPanelChatSessionStore()
    private static let storageKey = "CoderIDE.reviewPanelChatSessions.v1"

    @Published private(set) var conversationsByKey: [String: ReviewPanelChatConversationState] = [:]

    init() {
        load()
    }

    func conversation(for key: String) -> ReviewPanelChatConversationState {
        conversationsByKey[key] ?? .empty
    }

    func state(for key: String) -> ReviewPanelChatSessionState {
        activeState(for: key)
    }

    func activeState(for key: String) -> ReviewPanelChatSessionState {
        let conversation = conversation(for: key)
        guard let activeThreadId = conversation.activeThreadId,
              let thread = conversation.threads.first(where: { $0.id == activeThreadId }) else {
            return .empty
        }
        return thread.sessionState
    }

    func createThread(for key: String, title: String? = nil) -> String {
        var conversation = conversation(for: key)
        let id = UUID().uuidString.lowercased()
        let index = conversation.threads.count + 1
        let thread = ReviewPanelChatThreadState(
            id: id,
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Chat \(index)"
        )
        conversation.threads.insert(thread, at: 0)
        conversation.activeThreadId = id
        conversationsByKey[key] = conversation
        save()
        return id
    }

    func replaceActiveState(_ state: ReviewPanelChatSessionState, for key: String) {
        let threadId = ensureActiveThread(for: key)
        updateThread(threadId: threadId, for: key) { thread in
            thread.apply(state)
        }
    }

    func replaceState(_ state: ReviewPanelChatSessionState, for key: String) {
        replaceActiveState(state, for: key)
    }

    func appendMessage(_ message: ReviewPanelMessage, for key: String) {
        let threadId = ensureActiveThread(for: key)
        updateThread(threadId: threadId, for: key) { thread in
            thread.messages.append(message)
            thread.updatedAt = Date()
            if thread.title.hasPrefix("Chat "),
               message.role == .user,
               let derived = Self.derivedTitle(from: message.content) {
                thread.title = derived
            }
        }
    }

    func updateMessage(
        id: UUID,
        for key: String,
        mutate: (inout ReviewPanelMessage) -> Void
    ) {
        let threadId = ensureActiveThread(for: key)
        updateThread(threadId: threadId, for: key) { thread in
            guard let index = thread.messages.firstIndex(where: { $0.id == id }) else { return }
            mutate(&thread.messages[index])
            thread.updatedAt = Date()
        }
    }

    func setProcessing(_ isProcessing: Bool, startedAt: Date?, for key: String) {
        let threadId = ensureActiveThread(for: key)
        updateThread(threadId: threadId, for: key) { thread in
            thread.isProcessing = isProcessing
            thread.startedAt = startedAt
            thread.updatedAt = Date()
        }
    }

    func selectThread(_ threadId: String, for key: String) {
        var conversation = conversation(for: key)
        guard conversation.threads.contains(where: { $0.id == threadId && !$0.archived }) else { return }
        conversation.activeThreadId = threadId
        conversationsByKey[key] = conversation
        save()
    }

    func archiveThread(_ threadId: String, for key: String) {
        updateThread(threadId: threadId, for: key) { thread in
            thread.archived = true
            thread.updatedAt = Date()
        }
        normalizeActiveThread(for: key)
    }

    func restoreThread(_ threadId: String, for key: String) {
        updateThread(threadId: threadId, for: key) { thread in
            thread.archived = false
            thread.updatedAt = Date()
        }
        save()
    }

    func deleteThread(_ threadId: String, for key: String) {
        var conversation = conversation(for: key)
        conversation.threads.removeAll { $0.id == threadId }
        if conversation.threads.isEmpty {
            conversation.activeThreadId = nil
        } else if conversation.activeThreadId == threadId {
            conversation.activeThreadId = conversation.threads.first(where: { !$0.archived })?.id
                ?? conversation.threads.first?.id
        }
        conversationsByKey[key] = conversation
        save()
    }

    func clearState(for key: String) {
        conversationsByKey[key] = .empty
        save()
    }

    func clearAll() {
        conversationsByKey.removeAll()
        save()
    }

    private func ensureActiveThread(for key: String) -> String {
        let conversation = conversation(for: key)
        if let activeThreadId = conversation.activeThreadId,
           conversation.threads.contains(where: { $0.id == activeThreadId }) {
            return activeThreadId
        }
        return createThread(for: key)
    }

    private func updateThread(
        threadId: String,
        for key: String,
        mutate: (inout ReviewPanelChatThreadState) -> Void
    ) {
        var conversation = conversation(for: key)
        guard let index = conversation.threads.firstIndex(where: { $0.id == threadId }) else { return }
        mutate(&conversation.threads[index])
        conversation.threads.sort { $0.updatedAt > $1.updatedAt }
        conversationsByKey[key] = conversation
        save()
    }

    private func normalizeActiveThread(for key: String) {
        var conversation = conversation(for: key)
        if let activeThreadId = conversation.activeThreadId,
           let thread = conversation.threads.first(where: { $0.id == activeThreadId }),
           !thread.archived {
            conversationsByKey[key] = conversation
            return
        }
        conversation.activeThreadId = conversation.threads.first(where: { !$0.archived })?.id
        conversationsByKey[key] = conversation
        save()
    }

    private static func derivedTitle(from content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(36))
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else {
            conversationsByKey = [:]
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        conversationsByKey =
            (try? decoder.decode([String: ReviewPanelChatConversationState].self, from: data))
            ?? [:]
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(conversationsByKey) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

struct ReviewPanelChatConversationState: Equatable, Codable {
    var threads: [ReviewPanelChatThreadState]
    var activeThreadId: String?

    static let empty = ReviewPanelChatConversationState(
        threads: [],
        activeThreadId: nil
    )
}

struct ReviewPanelChatThreadState: Identifiable, Equatable, Codable {
    let id: String
    var title: String
    var messages: [ReviewPanelMessage]
    var isProcessing: Bool
    var startedAt: Date?
    var updatedAt: Date
    var archived: Bool

    init(
        id: String = UUID().uuidString.lowercased(),
        title: String,
        messages: [ReviewPanelMessage] = [],
        isProcessing: Bool = false,
        startedAt: Date? = nil,
        updatedAt: Date = Date(),
        archived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.isProcessing = isProcessing
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.archived = archived
    }

    var sessionState: ReviewPanelChatSessionState {
        ReviewPanelChatSessionState(
            messages: messages,
            isProcessing: isProcessing,
            startedAt: startedAt
        )
    }

    var subtitle: String {
        if isProcessing {
            return "Live"
        }
        return messages.last?.content.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "No messages yet"
    }

    mutating func apply(_ state: ReviewPanelChatSessionState) {
        messages = state.messages
        isProcessing = state.isProcessing
        startedAt = state.startedAt
        updatedAt = Date()
    }
}

struct ReviewPanelChatSessionState: Equatable, Codable {
    var messages: [ReviewPanelMessage]
    var isProcessing: Bool
    var startedAt: Date?

    static let empty = ReviewPanelChatSessionState(
        messages: [],
        isProcessing: false,
        startedAt: nil
    )
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
