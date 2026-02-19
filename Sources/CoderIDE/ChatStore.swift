import SwiftUI
import CoderEngine

struct ChatMessage: Identifiable, Codable {
    var id: UUID
    var role: Role
    var content: String
    var isStreaming: Bool
    
    enum Role: String, Codable {
        case user
        case assistant
    }
    
    init(id: UUID = UUID(), role: Role, content: String, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
    }
}

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var workspaceId: UUID?
    var adHocFolderPaths: [String]
    
    init(id: UUID = UUID(), title: String = "Nuova conversazione", messages: [ChatMessage] = [], createdAt: Date = .now, workspaceId: UUID? = nil, adHocFolderPaths: [String] = []) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.workspaceId = workspaceId
        self.adHocFolderPaths = adHocFolderPaths
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, title, messages, createdAt, workspaceId, adHocFolderPaths
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        messages = try c.decode([ChatMessage].self, forKey: .messages)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        workspaceId = try? c.decode(UUID.self, forKey: .workspaceId)
        adHocFolderPaths = (try? c.decode([String].self, forKey: .adHocFolderPaths)) ?? []
    }
}

private let conversationsStorageKey = "CoderIDE.conversations"

@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var isLoading = false
    @Published var taskStartDate: Date?
    
    init() {
        loadConversations()
        if conversations.isEmpty {
            createConversation()
        }
    }
    
    private func loadConversations() {
        guard let data = UserDefaults.standard.data(forKey: conversationsStorageKey),
              let decoded = try? JSONDecoder().decode([Conversation].self, from: data) else {
            return
        }
        conversations = decoded
    }
    
    func saveConversations() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        UserDefaults.standard.set(data, forKey: conversationsStorageKey)
    }
    
    @discardableResult
    func createConversation(workspaceId: UUID? = nil, adHocFolderPaths: [String] = []) -> UUID {
        let conv = Conversation(workspaceId: workspaceId, adHocFolderPaths: adHocFolderPaths)
        conversations.append(conv)
        saveConversations()
        return conv.id
    }
    
    func deleteConversation(id: UUID) {
        conversations.removeAll { $0.id == id }
        if conversations.isEmpty { createConversation() }
        saveConversations()
    }

    func clearWorkspaceReferences(workspaceId: UUID) {
        for i in conversations.indices where conversations[i].workspaceId == workspaceId {
            conversations[i].workspaceId = nil
        }
        saveConversations()
    }

    func setWorkspace(conversationId: UUID?, workspaceId: UUID?) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].workspaceId = workspaceId
        conversations[idx].adHocFolderPaths = []
        saveConversations()
    }
    
    func setAdHocPaths(conversationId: UUID?, paths: [String]) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].workspaceId = nil
        conversations[idx].adHocFolderPaths = paths
        saveConversations()
    }
    
    func conversation(for id: UUID?) -> Conversation? {
        guard let id else { return nil }
        return conversations.first { $0.id == id }
    }
    
    func addMessage(_ message: ChatMessage, to conversationId: UUID?) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].messages.append(message)
        if conversations[idx].title == "Nuova conversazione", case .user = message.role {
            conversations[idx].title = String(message.content.prefix(40))
            if message.content.count > 40 { conversations[idx].title += "…" }
        }
        saveConversations()
    }
    
    func updateLastAssistantMessage(content: String, in conversationId: UUID?) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        guard let lastIdx = conversations[idx].messages.lastIndex(where: { $0.role == .assistant }) else { return }
        conversations[idx].messages[lastIdx].content = content
        saveConversations()
    }
    
    func setLastAssistantStreaming(_ streaming: Bool, in conversationId: UUID?) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        guard let lastIdx = conversations[idx].messages.lastIndex(where: { $0.role == .assistant }) else { return }
        conversations[idx].messages[lastIdx].isStreaming = streaming
        saveConversations()
    }
    
    func beginTask() {
        isLoading = true
        taskStartDate = Date()
    }
    
    func endTask() {
        isLoading = false
        taskStartDate = nil
    }
}
