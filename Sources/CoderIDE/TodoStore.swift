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

    init(
        id: UUID = UUID(),
        title: String,
        status: TodoStatus = .pending,
        priority: TodoPriority = .medium,
        source: TodoSource = .manual,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        notes: String = "",
        linkedFiles: [String] = []
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, completed, status, priority, source, createdAt, updatedAt, notes, linkedFiles
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
    }
}

enum TodoFilter: String, CaseIterable {
    case open = "Aperti"
    case inProgress = "In corso"
    case completed = "Completati"
}

private let todosStorageKey = "CoderIDE.todos"

@MainActor
final class TodoStore: ObservableObject {
    @Published var todos: [TodoItem] = []
    @Published var filter: TodoFilter = .open

    init() {
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

        return filtered.sorted {
            if $0.status.rank != $1.status.rank { return $0.status.rank < $1.status.rank }
            if $0.priority.rank != $1.priority.rank { return $0.priority.rank < $1.priority.rank }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var completionRatio: Double {
        guard !todos.isEmpty else { return 0 }
        let done = Double(todos.filter { $0.status == .done }.count)
        return done / Double(todos.count)
    }

    private func loadTodos() {
        guard let data = UserDefaults.standard.data(forKey: todosStorageKey),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else {
            return
        }
        todos = decoded
    }

    private func saveTodos() {
        guard let data = try? JSONEncoder().encode(todos) else { return }
        UserDefaults.standard.set(data, forKey: todosStorageKey)
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

    func clearAgentTodos() {
        todos.removeAll { $0.source == .agent }
        saveTodos()
    }
}
