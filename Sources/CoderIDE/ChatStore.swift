import SwiftUI
import CoderEngine

struct PlanAttachment: Codable, Equatable {
    var historyEntryId: UUID
    var layoutVersion: Int
    var showExpand: Bool
    var snapshotTitle: String
}

struct ChatMessage: Identifiable, Codable {
    var id: UUID
    var role: Role
    var content: String
    var isStreaming: Bool
    var imagePaths: [String]?
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
        planAttachment: PlanAttachment? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.imagePaths = imagePaths
        self.planAttachment = planAttachment
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
        title: String = "Nuova conversazione",
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

@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var isLoading = false
    @Published var taskStartDate: Date?
    @Published var activeTaskConversationId: UUID?
    @Published private(set) var planBoards: [UUID: PlanBoard] = [:]

    init() {
        loadConversations()
        loadPlanBoards()
        if conversations.isEmpty {
            createConversation(contextId: nil, contextFolderPath: nil, mode: nil)
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
        Usa esclusivamente il contesto dei thread trovati qui sotto per rispondere alla mia domanda.
        Se il contesto non basta, dillo chiaramente.

        Query di ricerca: \(query)

        Risultati thread:
        \(items)

        Domanda:
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

    func isAssistantStreaming(in conversationId: UUID?) -> Bool {
        guard let conversation = conversation(for: conversationId) else { return false }
        guard let lastAssistant = conversation.messages.last(where: { $0.role == .assistant }) else {
            return false
        }
        return lastAssistant.isStreaming
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

    /// - Parameter persistImmediately: se false, salta saveConversations (usare durante streaming per non bloccare il main thread con I/O).
    func updateLastAssistantMessage(content: String, in conversationId: UUID?, persistImmediately: Bool = true) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        guard let lastIdx = conversations[idx].messages.lastIndex(where: { $0.role == .assistant }) else { return }
        // Durante lo streaming usa una sanitizzazione conservativa:
        // evita di eliminare frasi "operative" legittime che altrimenti fanno sembrare
        // il testo bloccato dopo il primo chunk.
        let stripped = Self.stripCoderideMarkers(content, aggressive: persistImmediately)
        let rawTrimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedContent: String
        if stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !rawTrimmed.isEmpty {
            // Fallback difensivo: non perdere mai il contenuto assistant su provider non-Codex.
            // Se la sanitizzazione aggressiva svuota tutto, riprova in modalita` conservativa.
            let conservative = Self.stripCoderideMarkers(content, aggressive: false)
            resolvedContent = conservative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? content
                : conservative
        } else {
            resolvedContent = stripped
        }
        var conv = conversations[idx]
        var msgs = conv.messages
        var msg = msgs[lastIdx]
        msg.content = resolvedContent
        msgs[lastIdx] = msg
        conv.messages = msgs
        var updated = conversations
        updated[idx] = conv
        conversations = updated
        if persistImmediately { saveConversations() }
    }

    /// Rimuove marker CODERIDE alla sorgente per evitare flash durante lo streaming.
    static func stripCoderideMarkers(_ content: String, aggressive: Bool = true) -> String {
        var out = content
        // 1. Standard [CODERIDE:...] markers (regex)
        if let regex = try? NSRegularExpression(
            pattern: "\\[\\s*CODERIDE\\s*:[^\\]\\n]*\\]",
            options: .caseInsensitive
        ) {
            while true {
                let ns = out as NSString
                guard let match = regex.firstMatch(in: out, range: NSRange(location: 0, length: ns.length))
                else { break }
                let start = out.index(out.startIndex, offsetBy: match.range.location)
                let end = out.index(start, offsetBy: match.range.length)
                out.removeSubrange(start..<end)
            }
        }
        // 2. Fallback for incomplete [CODERIDE markers
        // Durante lo streaming possono arrivare frammenti marker non ancora chiusi.
        // Rimuoviamo solo la porzione di riga "sporca" per evitare di cancellare
        // anche il testo assistant valido che segue nelle righe successive.
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
            // 3. Strip operational status lines that leak into output
            // e.g. "Creating detailed Italian planIDE:files=README.md]"
            if let statusLineRegex = try? NSRegularExpression(
                pattern: #"^[^\n]*IDE\s*:\s*files\s*=[^\]\n]*\]?\s*"#,
                options: [.caseInsensitive, .anchorsMatchLines]
            ) {
                let ns = out as NSString
                out = statusLineRegex.stringByReplacingMatches(
                    in: out, range: NSRange(location: 0, length: ns.length), withTemplate: ""
                )
            }
            // 4. Strip lines that are purely operational prefixes (e.g. "Creating detailed..." followed by IDE markers)
            if let opLineRegex = try? NSRegularExpression(
                pattern: #"^(?:Creating|Generating|Processing|Analyzing|Reading|Writing|Updating)\s+[^\n]*?(?:IDE|CODERIDE|planIDE)[^\n]*$"#,
                options: [.caseInsensitive, .anchorsMatchLines]
            ) {
                let ns = out as NSString
                out = opLineRegex.stringByReplacingMatches(
                    in: out, range: NSRange(location: 0, length: ns.length), withTemplate: ""
                )
            }
            // 4b. Rimuove boilerplate operativi iniziali prima della risposta utile.
            if let bugReviewRegex = try? NSRegularExpression(
                pattern: #"(?im)^Planning\s+(?:bug\s+review|code\s+review)\s+workflow\s*$"#,
                options: [.caseInsensitive, .anchorsMatchLines]
            ) {
                let ns = out as NSString
                out = bugReviewRegex.stringByReplacingMatches(
                    in: out, range: NSRange(location: 0, length: ns.length), withTemplate: ""
                )
            }
            // 4b-1. Se la riga contiene prefisso operativo + contenuto utile sulla stessa riga,
            // rimuove solo il prefisso iniziale e preserva il testo che segue.
            if let inlineOperationalPrefixRegex = try? NSRegularExpression(
                pattern: #"(?im)^(\s*(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing|Inspecting)\s+(?:initial\s+)?(?:task\s+panel(?:\s+and\s+todo\s+update)?|todo(?:\s+update)?|workflow(?:\s+steps?)?|project\s+analysis|analysis|plan|execution(?:\s+flow)?)(?:\s+and\s+todo\s+update)?\s+)"#,
                options: [.caseInsensitive, .anchorsMatchLines]
            ) {
                let ns = out as NSString
                out = inlineOperationalPrefixRegex.stringByReplacingMatches(
                    in: out, range: NSRange(location: 0, length: ns.length), withTemplate: ""
                )
            }
            if let initBoilerplateRegex = try? NSRegularExpression(
                pattern: #"(?im)^(?:(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing)\s+(?:initial\s+)?(?:task\s+panel|todo|workflow|workflow\s+steps?|project\s+analysis|analysis|plan|execution|execution\s+flow|operations?)\b[^\n]*|(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing)\s+[^\n]*(?:task\s+panel|todo|workflow|analysis|plan|execution)\b[^\n]*)$"#,
                options: [.caseInsensitive, .anchorsMatchLines]
            ) {
                let ns = out as NSString
                out = initBoilerplateRegex.stringByReplacingMatches(
                    in: out, range: NSRange(location: 0, length: ns.length), withTemplate: ""
                )
            }
            // 4c. Rimuove heading/righe operative di "progress commentary" trapelate nello stream.
            if let progressHeadingRegex = try? NSRegularExpression(
                pattern: #"(?im)^(?:\*{1,2}\s*)?(?:Updating|Planning|Reading|Analyzing|Implementing)\b[^\n]{0,140}(?:\*{1,2})?\s*$"#,
                options: [.caseInsensitive, .anchorsMatchLines]
            ) {
                let ns = out as NSString
                out = progressHeadingRegex.stringByReplacingMatches(
                    in: out, range: NSRange(location: 0, length: ns.length), withTemplate: ""
                )
            }
            // 4d. Rimuove righe di progress tecnico non utili al testo utente finale.
            if let cliTraceRegex = try? NSRegularExpression(
                pattern: #"(?im)^(?:Explored\s+\d+\s+files?(?:,\s*\d+\s+search(?:es)?)?(?:,\s*\d+\s+list)?|Ran\s+[^\n]+|Inspecting\s+[^\n]+)\s*$"#,
                options: [.caseInsensitive, .anchorsMatchLines]
            ) {
                let ns = out as NSString
                out = cliTraceRegex.stringByReplacingMatches(
                    in: out, range: NSRange(location: 0, length: ns.length), withTemplate: ""
                )
            }
        }
        // Marker inline "markers:todo_write|..." o "todo_write|..."
        out = out.replacingOccurrences(
            of: #"(?i)\bmarkers\s*:\s*[a-z_][a-z0-9_]*\|"#,
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"(?i)\b(?:todo_write|todo_read|plan_step(?:_update)?|read_batch(?:_started|_completed)?|web_search(?:_started|_completed|_failed)?|instant_grep)\|"#,
            with: "",
            options: .regularExpression
        )
        // Varianti spezzate/troncate dei marker operativi (es. "do_write|", "markersdo_write|").
        out = out.replacingOccurrences(
            of: #"(?i)\b(?:markers)?[a-z_]*(?:todo_write|todo_read|do_write|do_read|plan_step(?:_update)?|read_batch(?:_started|_completed)?|web_search(?:_started|_completed|_failed)?|instant_grep)\|"#,
            with: "",
            options: .regularExpression
        )
        // Eventi tecnici che non devono mai apparire nel testo utente.
        out = out.replacingOccurrences(
            of: #"(?i)\b(?:coderide_show_task_panel|coderide_invoke_swarm|read_batch_started|read_batch_completed|web_search_started|web_search_completed|web_search_failed|plan_step(?:_update)?|todo_write|todo_read|instant_grep)\b"#,
            with: "",
            options: .regularExpression
        )
        if aggressive {
            // Se un marker si incolla al testo, separa il token key=value prima della rimozione.
            out = out.replacingOccurrences(
                of: #"([A-Za-zÀ-ÖØ-öø-ÿ])((?i:files|count|group_id|queryid|query|step_id|pathscope|matchescount|previewlines|status|priority|notes|title|id|task)=)"#,
                with: "$1 $2",
                options: .regularExpression
            )
            // Rimuove singoli frammenti key=value tipici dei marker operativi.
            out = out.replacingOccurrences(
                of: #"(?i)\b(?:id|title|status|priority|notes|files|step_id|queryid|query|group_id|count|task)=[^|\n\r]+(?:\||$)"#,
                with: "",
                options: .regularExpression
            )
            // Fallback key=value con chiusura ] (es. files=Sources/..]).
            out = out.replacingOccurrences(
                of: #"(?i)\b(?:id|title|status|priority|notes|files|step_id|queryid|query|group_id|count|task|pathscope|matchescount|previewlines)=[^\]\n\r]+\]"#,
                with: "",
                options: .regularExpression
            )
            // Fallback robusto: rimuove payload marker "grezzi" trapelati nel testo
            // (es. id=t1|title=...|status=...|priority=...|notes=...|files=...|).
            out = stripStructuredMarkerPayloads(out)
        }
        // Cleanup formattazione leggibile (stile chat): spazi, punteggiatura, line breaks.
        out = out.replacingOccurrences(of: #"\s+\n"#, with: "\n", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        out = out.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        out = out.replacingOccurrences(
            of: #"([.!?])([A-Za-zÀ-ÖØ-öø-ÿ])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        let normalized = out.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        return aggressive ? normalized.trimmingCharacters(in: .whitespacesAndNewlines) : normalized
    }

    private static func stripStructuredMarkerPayloads(_ input: String) -> String {
        let markerKeys: Set<String> = [
            "id", "title", "status", "priority", "notes", "files", "step_id",
            "queryid", "query", "group_id", "count", "task",
        ]
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(?:\b[a-z_][a-z0-9_]*=[^|\n\r]+(?:\|\s*|\s*$)){2,}"#,
            options: []
        ) else {
            return input
        }
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
                let markerKeyCount = keys.filter { markerKeys.contains($0) }.count
                if markerKeyCount >= 3 {
                    out.removeSubrange(strRange)
                    removed = true
                }
            }
            if !removed { break }
        }
        return out
    }

    /// Estrae l'ultima riga "operativa" dal contenuto durante lo streaming (es. "Planning next moves", "Explored lints").
    /// Usata per mostrare il thinking dell'LLM come su Cursor.
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
        isLoading = true
        taskStartDate = Date()
        activeTaskConversationId = conversationId
    }

    // Compat legacy call sites.
    func beginTask() {
        beginTask(conversationId: activeTaskConversationId)
    }

    func endTask(conversationId: UUID?) {
        // Evita che uno stop fuori contesto resetti task ancora attivo in altro thread.
        if let active = activeTaskConversationId,
            let conversationId,
            active != conversationId
        {
            return
        }
        isLoading = false
        taskStartDate = nil
        activeTaskConversationId = nil
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

    func upsertPlanStep(
        stepId: String,
        status: PlanStepStatus,
        title: String? = nil,
        in conversationId: UUID?
    ) {
        guard let conversationId else { return }
        var board = planBoards[conversationId] ?? PlanBoard(
            goal: "Piano operativo in corso",
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
        guard msgs.count > keepLast + 2 else { return false }
        let toSummarize = Array(msgs.prefix(msgs.count - keepLast))
        let recent = Array(msgs.suffix(keepLast))
        let textToSummarize = toSummarize.map { message in
            let roleLabel = message.role == .user ? "Utente" : "Assistant"
            return "\(roleLabel): \(message.content)"
        }.joined(separator: "\n\n")
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
            activeFilePath: nil,
            activeRootPath: context.activeRootPath
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
