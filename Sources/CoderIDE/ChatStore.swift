import SwiftUI
import CoderEngine

struct ChatMessage: Identifiable, Codable {
    var id: UUID
    var role: Role
    var content: String
    var isStreaming: Bool
    var imagePaths: [String]?

    enum Role: String, Codable {
        case user
        case assistant
    }

    init(id: UUID = UUID(), role: Role, content: String, isStreaming: Bool = false, imagePaths: [String]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.imagePaths = imagePaths
    }
}

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var workspaceId: UUID?
    var adHocFolderPaths: [String]
    var mode: CoderMode?

    init(id: UUID = UUID(), title: String = "Nuova conversazione", messages: [ChatMessage] = [], createdAt: Date = .now, workspaceId: UUID? = nil, adHocFolderPaths: [String] = [], mode: CoderMode? = nil) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.workspaceId = workspaceId
        self.adHocFolderPaths = adHocFolderPaths
        self.mode = mode
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, messages, createdAt, workspaceId, adHocFolderPaths, mode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        messages = try c.decode([ChatMessage].self, forKey: .messages)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        workspaceId = try? c.decode(UUID.self, forKey: .workspaceId)
        adHocFolderPaths = (try? c.decode([String].self, forKey: .adHocFolderPaths)) ?? []
        if let raw = try? c.decode(String.self, forKey: .mode), let m = CoderMode(rawValue: raw) {
            mode = m
        } else {
            mode = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(messages, forKey: .messages)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(workspaceId, forKey: .workspaceId)
        try c.encode(adHocFolderPaths, forKey: .adHocFolderPaths)
        try c.encode(mode?.rawValue, forKey: .mode)
    }
}

private let conversationsStorageKey = "CoderIDE.conversations"
private let planBoardsStorageKey = "CoderIDE.planBoards"

@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var isLoading = false
    @Published var taskStartDate: Date?
    @Published private(set) var planBoards: [UUID: PlanBoard] = [:]

    init() {
        loadConversations()
        loadPlanBoards()
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

    private func loadPlanBoards() {
        guard let data = UserDefaults.standard.data(forKey: planBoardsStorageKey),
              let decoded = try? JSONDecoder().decode([String: PlanBoard].self, from: data) else {
            return
        }
        planBoards = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            guard let uuid = UUID(uuidString: key) else { return nil }
            return (uuid, value)
        })
    }

    private func savePlanBoards() {
        let serialized = Dictionary(uniqueKeysWithValues: planBoards.map { ($0.key.uuidString, $0.value) })
        guard let data = try? JSONEncoder().encode(serialized) else { return }
        UserDefaults.standard.set(data, forKey: planBoardsStorageKey)
    }

    @discardableResult
    func createConversation(workspaceId: UUID? = nil, adHocFolderPaths: [String] = [], mode: CoderMode? = nil) -> UUID {
        let conv = Conversation(workspaceId: workspaceId, adHocFolderPaths: adHocFolderPaths, mode: mode)
        conversations.append(conv)
        saveConversations()
        return conv.id
    }

    /// Trova o crea una conversazione per (workspaceId, mode). Per match usa workspaceId e mode; conv senza mode (legacy) non vengono restituite.
    func conversationForMode(workspaceId: UUID?, mode: CoderMode, adHocFolderPaths: [String] = []) -> Conversation? {
        conversations.first { conv in
            conv.workspaceId == workspaceId && conv.mode == mode && (adHocFolderPaths.isEmpty || Set(conv.adHocFolderPaths) == Set(adHocFolderPaths))
        }
    }

    /// Trova o crea una conversazione per il mode dato; restituisce l'id da usare come selectedConversationId.
    @discardableResult
    func getOrCreateConversationForMode(workspaceId: UUID?, mode: CoderMode, adHocFolderPaths: [String] = []) -> UUID {
        if let existing = conversationForMode(workspaceId: workspaceId, mode: mode, adHocFolderPaths: adHocFolderPaths) {
            return existing.id
        }
        return createConversation(workspaceId: workspaceId, adHocFolderPaths: adHocFolderPaths, mode: mode)
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

    func setPlanBoard(_ board: PlanBoard, for conversationId: UUID?) {
        guard let conversationId else { return }
        planBoards[conversationId] = board
        savePlanBoards()
    }

    func choosePlanPath(_ chosenPath: String, for conversationId: UUID?) {
        guard let conversationId, var board = planBoards[conversationId] else { return }
        board.chosenPath = chosenPath
        board.updatedAt = .now
        planBoards[conversationId] = board
        savePlanBoards()
    }

    func planBoard(for conversationId: UUID?) -> PlanBoard? {
        guard let conversationId else { return nil }
        return planBoards[conversationId]
    }

    func updatePlanStepStatus(stepId: String, status: PlanStepStatus, in conversationId: UUID?) {
        guard let conversationId, var board = planBoards[conversationId] else { return }
        guard let index = board.steps.firstIndex(where: { $0.id == stepId }) else { return }
        board.steps[index].status = status
        board.updatedAt = .now
        planBoards[conversationId] = board
        savePlanBoards()
    }

    /// Comprime la history con un riassunto quando il contesto si riempie (stile Cursor)
    func summarizeConversation(
        id: UUID?,
        keepLast: Int,
        provider: any CoderEngine.LLMProvider,
        context: CoderEngine.WorkspaceContext
    ) async throws -> Bool {
        guard let cid = id, let idx = conversations.firstIndex(where: { $0.id == cid }) else { return false }
        let msgs = conversations[idx].messages
        guard msgs.count > keepLast + 2 else { return false }
        let toSummarize = Array(msgs.prefix(msgs.count - keepLast))
        let recent = Array(msgs.suffix(keepLast))
        let textToSummarize = toSummarize.map { "\($0.role == .user ? "Utente" : "Assistant"): \($0.content)" }.joined(separator: "\n\n")
        let prompt = """
        Riassumi questa conversazione mantenendo: obiettivi, decisioni prese, file modificati, errori rilevati, passi completati.
        Non includere dettagli di codice non necessari.

        Conversazione:
        \(textToSummarize)

        Rispondi solo con il riassunto, senza premesse.
        """
        let ctx = CoderEngine.WorkspaceContext(
            workspacePaths: context.workspacePaths,
            isNamedWorkspace: false,
            workspaceName: nil,
            excludedPaths: [],
            openFiles: [],
            activeSelection: nil,
            activeFilePath: nil
        )
        let stream = try await provider.send(prompt: prompt, context: ctx, imageURLs: nil)
        var summary = ""
        for try await ev in stream {
            if case .textDelta(let d) = ev { summary += d }
            if case .error(let e) = ev { summary += "\n[Errore: \(e)]" }
        }
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let summaryMsg = ChatMessage(
            role: .assistant,
            content: "[Riassunto precedente]\n\n\(summary.trimmingCharacters(in: .whitespacesAndNewlines))",
            isStreaming: false
        )
        conversations[idx].messages = [summaryMsg] + recent
        saveConversations()
        return true
    }
}
