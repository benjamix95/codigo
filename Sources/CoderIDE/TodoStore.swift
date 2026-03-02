import SwiftUI
import CoderEngine

enum TodoStatus: String, Codable, CaseIterable {
    case pending
    case inProgress = "in_progress"
    case blocked
    case done

    var rank: Int {
        switch self {
        case .inProgress: return 0
        case .pending: return 1
        case .blocked: return 2
        case .done: return 3
        }
    }

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "circle.inset.filled"
        case .blocked: return "exclamationmark.circle"
        case .done: return "checkmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .pending: return "OPEN"
        case .inProgress: return "DOING"
        case .blocked: return "BLOCKED"
        case .done: return "DONE"
        }
    }

    var color: Color {
        switch self {
        case .pending: return DesignSystem.Colors.textSecondary
        case .inProgress: return DesignSystem.Colors.planColor
        case .blocked: return DesignSystem.Colors.error
        case .done: return DesignSystem.Colors.success
        }
    }
}

enum TodoPriority: String, Codable, CaseIterable {
    case low
    case medium
    case high

    var rank: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }

    var color: Color {
        switch self {
        case .low: return DesignSystem.Colors.textTertiary
        case .medium: return DesignSystem.Colors.info
        case .high: return DesignSystem.Colors.error
        }
    }
}

enum TodoSource: String, Codable {
    case manual
    case agent
}

struct TodoItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var status: TodoStatus
    var priority: TodoPriority
    var source: TodoSource
    let createdAt: Date
    var updatedAt: Date
    var notes: String
    var linkedFiles: [String]
    var isPlanCanonical: Bool
    /// Conversation that owns this canonical plan todo.
    var planConversationId: UUID?
    /// Present-tense label shown during execution (e.g. "Fixing bug").
    var activeForm: String

    init(
        id: UUID = UUID(),
        title: String,
        status: TodoStatus = .pending,
        priority: TodoPriority = .medium,
        source: TodoSource = .manual,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        notes: String = "",
        linkedFiles: [String] = [],
        isPlanCanonical: Bool = false,
        planConversationId: UUID? = nil,
        activeForm: String = ""
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.priority = priority
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
        self.linkedFiles = linkedFiles
        self.isPlanCanonical = isPlanCanonical
        self.planConversationId = planConversationId
        self.activeForm = activeForm
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, completed, status, priority, source, createdAt, updatedAt, notes, linkedFiles, isPlanCanonical, planConversationId, activeForm
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? .now

        if let parsedStatus = try? container.decode(TodoStatus.self, forKey: .status) {
            status = parsedStatus
        } else {
            let completed = (try? container.decode(Bool.self, forKey: .completed)) ?? false
            status = completed ? .done : .pending
        }

        priority = (try? container.decode(TodoPriority.self, forKey: .priority)) ?? .medium
        source = (try? container.decode(TodoSource.self, forKey: .source)) ?? .manual
        notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
        linkedFiles = (try? container.decode([String].self, forKey: .linkedFiles)) ?? []
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? createdAt
        isPlanCanonical = (try? container.decode(Bool.self, forKey: .isPlanCanonical)) ?? false
        if let parsedConversationId = try? container.decode(UUID.self, forKey: .planConversationId) {
            planConversationId = parsedConversationId
        } else if let legacyConversationId = try? container.decode(String.self, forKey: .planConversationId),
                  let parsed = UUID(uuidString: legacyConversationId.trimmingCharacters(in: .whitespacesAndNewlines)) {
            planConversationId = parsed
        } else {
            planConversationId = nil
        }
        activeForm = (try? container.decode(String.self, forKey: .activeForm)) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encode(source, forKey: .source)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(notes, forKey: .notes)
        try container.encode(linkedFiles, forKey: .linkedFiles)
        try container.encode(isPlanCanonical, forKey: .isPlanCanonical)
        try container.encodeIfPresent(planConversationId, forKey: .planConversationId)
        try container.encode(activeForm, forKey: .activeForm)
    }
}

enum TodoFilter: String, CaseIterable {
    case open = "Aperti"
    case inProgress = "In corso"
    case completed = "Completed"
}

private let todosStorageKey = "CoderIDE.todos"

@MainActor
final class TodoStore: ObservableObject {
    @Published var todos: [TodoItem] = []
    @Published var filter: TodoFilter = .open
    private let storageKey: String
    private let userDefaults: UserDefaults

    /// Callback invoked when a canonical todo's status changes, enabling plan board sync.
    var onCanonicalTodoStatusChange: ((String, TodoStatus, UUID?) -> Void)?

    private func canonicalKey(for title: String) -> String {
        title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: "", options: .regularExpression)
    }

    private func canonicalTokens(for key: String) -> Set<String> {
        Set(
            key
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private func isLikelyCanonicalMatch(titleKey: String, canonicalKey: String) -> Bool {
        let titleTokens = canonicalTokens(for: titleKey)
        let canonicalTokens = canonicalTokens(for: canonicalKey)

        guard titleTokens.count >= 2 && canonicalTokens.count >= 2 else {
            return false
        }
        if canonicalKey.count >= 12 && titleKey.count >= 12 {
            if canonicalKey.contains(titleKey) || titleKey.contains(canonicalKey) {
                return true
            }
        }

        let overlap = Double(titleTokens.intersection(canonicalTokens).count)
        guard overlap > 0 else { return false }
        let shortSetSize = min(titleTokens.count, canonicalTokens.count)
        guard shortSetSize > 0 else { return false }
        let overlapRatio = overlap / Double(shortSetSize)
        return overlapRatio >= 0.7 && overlap >= 2
    }

    private func sortCanonicalFirst(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.isPlanCanonical != rhs.isPlanCanonical { return lhs.isPlanCanonical }
        if lhs.priority.rank != rhs.priority.rank { return lhs.priority.rank < rhs.priority.rank }
        return lhs.createdAt < rhs.createdAt
    }

    func sortedCanonicalFirstTodos(_ items: [TodoItem]? = nil) -> [TodoItem] {
        (items ?? todos).sorted(by: sortCanonicalFirst(_:_:))
    }

    func canonicalTodos(for conversationId: UUID?) -> [TodoItem] {
        let canonical = todos.filter(\.isPlanCanonical)
        guard let conversationId else {
            return sortedCanonicalFirstTodos(canonical)
        }
        let scoped = canonical.filter { $0.planConversationId == conversationId }
        if !scoped.isEmpty {
            return sortedCanonicalFirstTodos(scoped)
        }
        let legacyUnscoped = canonical.filter { $0.planConversationId == nil }
        return sortedCanonicalFirstTodos(legacyUnscoped)
    }

    private func canonicalScopeFilter(for conversationId: UUID?) -> (TodoItem) -> Bool {
        guard let conversationId else {
            return { $0.isPlanCanonical }
        }
        let hasScoped = todos.contains { $0.isPlanCanonical && $0.planConversationId == conversationId }
        return { item in
            guard item.isPlanCanonical else { return false }
            if let scopedConversation = item.planConversationId {
                return scopedConversation == conversationId
            }
            return !hasScoped
        }
    }

    private func runtimeScopeFilter(for conversationId: UUID?) -> (TodoItem) -> Bool {
        guard let conversationId else {
            return { !$0.isPlanCanonical }
        }
        let hasScoped = todos.contains { !$0.isPlanCanonical && $0.planConversationId == conversationId }
        return { item in
            guard !item.isPlanCanonical else { return false }
            if let scopedConversation = item.planConversationId {
                return scopedConversation == conversationId
            }
            // Legacy fallback for older todos without conversation scoping.
            return !hasScoped
        }
    }

    init(
        storageKey: String = todosStorageKey,
        userDefaults: UserDefaults = .standard
    ) {
        self.storageKey = storageKey
        self.userDefaults = userDefaults
        loadTodos()
        // Ensure MCP `coderide_todo_read` sees the current in-memory state
        // immediately on startup, even before the first mutation/save cycle.
        syncToSharedState()
    }

    var visibleTodos: [TodoItem] {
        let filtered: [TodoItem]
        switch filter {
        case .open:
            filtered = todos.filter { $0.status != .done }
        case .inProgress:
            filtered = todos.filter { $0.status == .inProgress }
        case .completed:
            filtered = todos.filter { $0.status == .done }
        }

        return sortedCanonicalFirstTodos(filtered)
    }

    var completionRatio: Double {
        guard !todos.isEmpty else { return 0 }
        let done = Double(todos.filter { $0.status == .done }.count)
        return done / Double(todos.count)
    }

    var openTodosCount: Int {
        todos.filter { $0.status != .done }.count
    }

    var hasOpenTodos: Bool {
        openTodosCount > 0
    }

    private func loadTodos() {
        guard let data = userDefaults.data(forKey: storageKey) else { return }
        do {
            todos = try JSONDecoder().decode([TodoItem].self, from: data)
        } catch {
            print("[TodoStore] ⚠️ Failed to decode todos: \(error.localizedDescription)")
        }
    }

    private func saveTodos() {
        do {
            let data = try JSONEncoder().encode(todos)
            userDefaults.set(data, forKey: storageKey)
            syncToSharedState()
        } catch {
            print("[TodoStore] ⚠️ Failed to encode todos: \(error.localizedDescription)")
        }
    }

    /// Write current todos to the shared state file so the MCP server
    /// can serve them via `coderide_todo_read`.
    private func syncToSharedState() {
        let items: [[String: Any]] = todos.map { todo in
            var record: [String: Any] = [
                "id": todo.id.uuidString,
                "title": todo.title,
                "status": todo.status.rawValue,
                "priority": todo.priority.rawValue,
                "source": todo.source.rawValue,
                "notes": todo.notes,
                "isPlanCanonical": todo.isPlanCanonical,
                "activeForm": todo.activeForm,
                "linkedFiles": todo.linkedFiles,
            ]
            if let planConversationId = todo.planConversationId {
                record["planConversationId"] = planConversationId.uuidString
            }
            return record
        }
        MCPSharedState.writeTodos(items)
    }

    func add(title: String, source: TodoSource = .manual, priority: TodoPriority = .medium, notes: String = "", activeForm: String = "", linkedFiles: [String] = []) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.append(TodoItem(title: trimmed, priority: priority, source: source, notes: notes, linkedFiles: linkedFiles, activeForm: activeForm))
        saveTodos()
    }

    func upsertFromAgent(
        id: UUID?,
        title: String,
        status: TodoStatus?,
        priority: TodoPriority?,
        notes: String?,
        activeForm: String? = nil,
        linkedFiles: [String],
        conversationId: UUID? = nil
    ) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }
        let isRuntimeInScope = runtimeScopeFilter(for: conversationId)

        func applyActiveForm(at idx: Int) {
            if let activeForm, !activeForm.isEmpty { todos[idx].activeForm = activeForm }
        }

        if let id, let idx = todos.firstIndex(where: { $0.id == id }) {
            todos[idx].title = normalizedTitle
            if let status { todos[idx].status = status }
            if let priority { todos[idx].priority = priority }
            if let notes, !notes.isEmpty { todos[idx].notes = notes }
            if !linkedFiles.isEmpty { todos[idx].linkedFiles = linkedFiles }
            applyActiveForm(at: idx)
            todos[idx].source = .agent
            if let conversationId, !todos[idx].isPlanCanonical {
                todos[idx].planConversationId = conversationId
            }
            todos[idx].updatedAt = .now
            saveTodos()
            return
        }

        if let matchedCanonicalId = bindRuntimeTodoToCanonicalIfMatch(
            title: normalizedTitle,
            conversationId: conversationId
        ),
            let idx = todos.firstIndex(where: { $0.id == matchedCanonicalId })
        {
            if let status { todos[idx].status = status }
            if let priority { todos[idx].priority = priority }
            if let notes, !notes.isEmpty { todos[idx].notes = notes }
            if !linkedFiles.isEmpty { todos[idx].linkedFiles = linkedFiles }
            applyActiveForm(at: idx)
            todos[idx].source = .agent
            if let conversationId, !todos[idx].isPlanCanonical {
                todos[idx].planConversationId = conversationId
            }
            todos[idx].updatedAt = .now
            saveTodos()
            return
        }

        if let idx = todos.firstIndex(where: {
            isRuntimeInScope($0) && $0.title.caseInsensitiveCompare(normalizedTitle) == .orderedSame
        }) {
            if let status { todos[idx].status = status }
            if let priority { todos[idx].priority = priority }
            if let notes, !notes.isEmpty { todos[idx].notes = notes }
            if !linkedFiles.isEmpty { todos[idx].linkedFiles = linkedFiles }
            applyActiveForm(at: idx)
            todos[idx].source = .agent
            if let conversationId, !todos[idx].isPlanCanonical {
                todos[idx].planConversationId = conversationId
            }
            todos[idx].updatedAt = .now
            saveTodos()
            return
        }

        let newTodo = TodoItem(
            title: normalizedTitle,
            status: status ?? .pending,
            priority: priority ?? .medium,
            source: .agent,
            notes: notes ?? "",
            linkedFiles: linkedFiles,
            planConversationId: conversationId,
            activeForm: activeForm ?? ""
        )
        todos.append(newTodo)
        saveTodos()
    }

    @discardableResult
    func upsertCanonicalOnlyFromAgent(
        id: UUID?,
        title: String,
        status: TodoStatus?,
        priority: TodoPriority?,
        notes: String?,
        activeForm: String? = nil,
        linkedFiles: [String],
        conversationId: UUID? = nil
    ) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return false }
        let isInScope = canonicalScopeFilter(for: conversationId)

        func applyUpdate(at idx: Int) {
            todos[idx].title = normalizedTitle
            if let status { todos[idx].status = status }
            if let priority { todos[idx].priority = priority }
            if let notes, !notes.isEmpty { todos[idx].notes = notes }
            if !linkedFiles.isEmpty { todos[idx].linkedFiles = linkedFiles }
            if let activeForm, !activeForm.isEmpty { todos[idx].activeForm = activeForm }
            if let conversationId {
                todos[idx].planConversationId = conversationId
            }
            todos[idx].source = .agent
            todos[idx].updatedAt = .now
            saveTodos()
        }

        if let id, let idx = todos.firstIndex(where: { $0.id == id && isInScope($0) }) {
            applyUpdate(at: idx)
            return true
        }

        if let matchedCanonicalId = bindRuntimeTodoToCanonicalIfMatch(
            title: normalizedTitle,
            conversationId: conversationId
        ),
           let idx = todos.firstIndex(where: { $0.id == matchedCanonicalId && isInScope($0) }) {
            applyUpdate(at: idx)
            return true
        }

        if let idx = todos.firstIndex(where: {
            isInScope($0) && $0.title.caseInsensitiveCompare(normalizedTitle) == .orderedSame
        }) {
            applyUpdate(at: idx)
            return true
        }

        return false
    }

    @discardableResult
    func bindRuntimeTodoToCanonicalIfMatch(title: String, conversationId: UUID? = nil) -> UUID? {
        let key = canonicalKey(for: title)
        guard !key.isEmpty else { return nil }
        let inScope = canonicalScopeFilter(for: conversationId)
        if let exact = todos.first(where: { inScope($0) && canonicalKey(for: $0.title) == key }) {
            return exact.id
        }
        // Fallback fuzzy match only for sufficiently long canonical keys
        // to reduce accidental collisions with short or generic titles.
        guard key.count >= 12 else { return nil }
        return todos.first(where: {
            guard inScope($0) else { return false }
            let canonical = canonicalKey(for: $0.title)
            return isLikelyCanonicalMatch(titleKey: key, canonicalKey: canonical)
        })?.id
    }

    func upsertCanonicalPlanTodos(_ titles: [String], conversationId: UUID? = nil) {
        // Deduplicate by canonical key, keeping first occurrence.
        var seenKeys = Set<String>()
        let cleaned: [String] = titles.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = canonicalKey(for: trimmed)
            guard seenKeys.insert(key).inserted else { return nil }
            return trimmed
        }
        guard !cleaned.isEmpty else { return }
        let desiredKeys = seenKeys
        let isInScope = canonicalScopeFilter(for: conversationId)

        for idx in todos.indices where isInScope(todos[idx]) {
            let existingKey = canonicalKey(for: todos[idx].title)
            if !desiredKeys.contains(existingKey) {
                let oldStatus = todos[idx].status
                todos[idx].status = .blocked
                todos[idx].notes = "Removed from current plan"
                todos[idx].updatedAt = .now
                if oldStatus != .blocked {
                    onCanonicalTodoStatusChange?(
                        todos[idx].title,
                        .blocked,
                        todos[idx].planConversationId
                    )
                }
            }
        }

        for title in cleaned {
            let key = canonicalKey(for: title)
            if let idx = todos.firstIndex(where: {
                isInScope($0) && canonicalKey(for: $0.title) == key
            }) {
                todos[idx].title = title
                todos[idx].isPlanCanonical = true
                todos[idx].planConversationId = conversationId
                todos[idx].source = .agent
                if todos[idx].status == .blocked {
                    todos[idx].status = .pending
                }
                todos[idx].updatedAt = .now
            } else {
                todos.append(
                    TodoItem(
                        title: title,
                        status: .pending,
                        priority: .medium,
                        source: .agent,
                        notes: "",
                        linkedFiles: [],
                        isPlanCanonical: true,
                        planConversationId: conversationId
                    )
                )
            }
        }
        saveTodos()
    }

    func remove(id: UUID) {
        if let todo = todos.first(where: { $0.id == id }), todo.isPlanCanonical {
            onCanonicalTodoStatusChange?(todo.title, .blocked, todo.planConversationId)
        }
        todos.removeAll { $0.id == id }
        saveTodos()
    }

    func setStatus(id: UUID, status: TodoStatus) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        let oldStatus = todos[idx].status
        todos[idx].status = status
        if oldStatus == .inProgress, status != .inProgress {
            todos[idx].activeForm = ""
        }
        todos[idx].updatedAt = .now
        saveTodos()
        if todos[idx].isPlanCanonical, status != oldStatus {
            onCanonicalTodoStatusChange?(todos[idx].title, status, todos[idx].planConversationId)
        }
    }

    func setPriority(id: UUID, priority: TodoPriority) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[idx].priority = priority
        todos[idx].updatedAt = .now
        saveTodos()
    }

    func clear() {
        todos.removeAll()
        saveTodos()
    }

    func clearAgentTodos(includePlanCanonical: Bool = false) {
        if includePlanCanonical {
            todos.removeAll { $0.source == .agent }
        } else {
            todos.removeAll { $0.source == .agent && !$0.isPlanCanonical }
        }
        saveTodos()
    }
}
