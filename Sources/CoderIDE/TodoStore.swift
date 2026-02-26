import SwiftUI

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
        isPlanCanonical: Bool = false
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, completed, status, priority, source, createdAt, updatedAt, notes, linkedFiles, isPlanCanonical
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

    private func canonicalKey(for title: String) -> String {
        title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: "", options: .regularExpression)
    }

    private func sortCanonicalFirst(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.isPlanCanonical != rhs.isPlanCanonical { return lhs.isPlanCanonical }
        if lhs.status.rank != rhs.status.rank { return lhs.status.rank < rhs.status.rank }
        if lhs.priority.rank != rhs.priority.rank { return lhs.priority.rank < rhs.priority.rank }
        return lhs.updatedAt > rhs.updatedAt
    }

    func sortedCanonicalFirstTodos(_ items: [TodoItem]? = nil) -> [TodoItem] {
        (items ?? todos).sorted(by: sortCanonicalFirst(_:_:))
    }

    init(
        storageKey: String = todosStorageKey,
        userDefaults: UserDefaults = .standard
    ) {
        self.storageKey = storageKey
        self.userDefaults = userDefaults
        loadTodos()
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
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else {
            return
        }
        todos = decoded
    }

    private func saveTodos() {
        guard let data = try? JSONEncoder().encode(todos) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    func add(title: String, source: TodoSource = .manual, priority: TodoPriority = .medium, notes: String = "", linkedFiles: [String] = []) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.append(TodoItem(title: trimmed, priority: priority, source: source, notes: notes, linkedFiles: linkedFiles))
        saveTodos()
    }

    func upsertFromAgent(
        id: UUID?,
        title: String,
        status: TodoStatus?,
        priority: TodoPriority?,
        notes: String?,
        linkedFiles: [String]
    ) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }

        if let id, let idx = todos.firstIndex(where: { $0.id == id }) {
            todos[idx].title = normalizedTitle
            if let status { todos[idx].status = status }
            if let priority { todos[idx].priority = priority }
            if let notes, !notes.isEmpty { todos[idx].notes = notes }
            if !linkedFiles.isEmpty { todos[idx].linkedFiles = linkedFiles }
            todos[idx].source = .agent
            todos[idx].updatedAt = .now
            saveTodos()
            return
        }

        if let matchedCanonicalId = bindRuntimeTodoToCanonicalIfMatch(title: normalizedTitle),
            let idx = todos.firstIndex(where: { $0.id == matchedCanonicalId })
        {
            if let status { todos[idx].status = status }
            if let priority { todos[idx].priority = priority }
            if let notes, !notes.isEmpty { todos[idx].notes = notes }
            if !linkedFiles.isEmpty { todos[idx].linkedFiles = linkedFiles }
            todos[idx].source = .agent
            todos[idx].updatedAt = .now
            saveTodos()
            return
        }

        if let idx = todos.firstIndex(where: { $0.title.caseInsensitiveCompare(normalizedTitle) == .orderedSame }) {
            if let status { todos[idx].status = status }
            if let priority { todos[idx].priority = priority }
            if let notes, !notes.isEmpty { todos[idx].notes = notes }
            if !linkedFiles.isEmpty { todos[idx].linkedFiles = linkedFiles }
            todos[idx].source = .agent
            todos[idx].updatedAt = .now
            saveTodos()
            return
        }

        add(
            title: normalizedTitle,
            source: .agent,
            priority: priority ?? .medium,
            notes: notes ?? "",
            linkedFiles: linkedFiles
        )
        if let status, let idx = todos.indices.last {
            todos[idx].status = status
            todos[idx].updatedAt = .now
            saveTodos()
        }
    }

    @discardableResult
    func upsertCanonicalOnlyFromAgent(
        id: UUID?,
        title: String,
        status: TodoStatus?,
        priority: TodoPriority?,
        notes: String?,
        linkedFiles: [String]
    ) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return false }

        func applyUpdate(at idx: Int) {
            todos[idx].title = normalizedTitle
            if let status { todos[idx].status = status }
            if let priority { todos[idx].priority = priority }
            if let notes, !notes.isEmpty { todos[idx].notes = notes }
            if !linkedFiles.isEmpty { todos[idx].linkedFiles = linkedFiles }
            todos[idx].source = .agent
            todos[idx].updatedAt = .now
            saveTodos()
        }

        if let id, let idx = todos.firstIndex(where: { $0.id == id && $0.isPlanCanonical }) {
            applyUpdate(at: idx)
            return true
        }

        if let matchedCanonicalId = bindRuntimeTodoToCanonicalIfMatch(title: normalizedTitle),
           let idx = todos.firstIndex(where: { $0.id == matchedCanonicalId && $0.isPlanCanonical }) {
            applyUpdate(at: idx)
            return true
        }

        if let idx = todos.firstIndex(where: {
            $0.isPlanCanonical && $0.title.caseInsensitiveCompare(normalizedTitle) == .orderedSame
        }) {
            applyUpdate(at: idx)
            return true
        }

        return false
    }

    @discardableResult
    func bindRuntimeTodoToCanonicalIfMatch(title: String) -> UUID? {
        let key = canonicalKey(for: title)
        guard !key.isEmpty else { return nil }
        if let exact = todos.first(where: { $0.isPlanCanonical && canonicalKey(for: $0.title) == key }) {
            return exact.id
        }
        // Fallback contenitivo bidirezionale solo per chiavi sufficientemente lunghe.
        guard key.count >= 12 else { return nil }
        return todos.first(where: {
            guard $0.isPlanCanonical else { return false }
            let canonical = canonicalKey(for: $0.title)
            guard canonical.count >= 12 else { return false }
            return canonical.contains(key) || key.contains(canonical)
        })?.id
    }

    func upsertCanonicalPlanTodos(_ titles: [String]) {
        let cleaned = titles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let desiredKeys = Set(cleaned.map { canonicalKey(for: $0) })

        for idx in todos.indices where todos[idx].isPlanCanonical {
            let existingKey = canonicalKey(for: todos[idx].title)
            if !desiredKeys.contains(existingKey), todos[idx].status != .done {
                todos[idx].status = .blocked
                todos[idx].notes = "Removed from current plan"
                todos[idx].updatedAt = .now
            }
        }

        for title in cleaned {
            let key = canonicalKey(for: title)
            if let idx = todos.firstIndex(where: {
                $0.isPlanCanonical && canonicalKey(for: $0.title) == key
            }) {
                todos[idx].title = title
                todos[idx].isPlanCanonical = true
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
                        isPlanCanonical: true
                    )
                )
            }
        }
        saveTodos()
    }

    func remove(id: UUID) {
        todos.removeAll { $0.id == id }
        saveTodos()
    }

    func setStatus(id: UUID, status: TodoStatus) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[idx].status = status
        todos[idx].updatedAt = .now
        saveTodos()
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
