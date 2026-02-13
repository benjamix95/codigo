import SwiftUI

struct TodoItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var completed: Bool
    let createdAt: Date

    init(id: UUID = UUID(), title: String, completed: Bool = false, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.completed = completed
        self.createdAt = createdAt
    }
}

private let todosStorageKey = "CoderIDE.todos"

@MainActor
final class TodoStore: ObservableObject {
    @Published var todos: [TodoItem] = []
    @Published var inProgressTodoId: UUID?

    init() {
        loadTodos()
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

    func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.append(TodoItem(title: trimmed))
        saveTodos()
    }

    func remove(id: UUID) {
        todos.removeAll { $0.id == id }
        if inProgressTodoId == id {
            inProgressTodoId = todos.first(where: { !$0.completed })?.id
        }
        saveTodos()
    }

    func toggle(id: UUID) {
        if let idx = todos.firstIndex(where: { $0.id == id }) {
            todos[idx].completed.toggle()
            if todos[idx].completed {
                inProgressTodoId = nil
                if let next = todos.first(where: { !$0.completed }) {
                    inProgressTodoId = next.id
                }
            }
            saveTodos()
        }
    }

    func setInProgress(id: UUID?) {
        inProgressTodoId = id
        objectWillChange.send()
    }

    func handleRowTap(id: UUID) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        if todos[idx].completed {
            todos[idx].completed = false
            inProgressTodoId = nil
            saveTodos()
        } else if inProgressTodoId == id {
            todos[idx].completed = true
            inProgressTodoId = nil
            if let next = todos.first(where: { !$0.completed && $0.id != id }) {
                inProgressTodoId = next.id
            }
            saveTodos()
        } else {
            inProgressTodoId = id
            objectWillChange.send()
        }
    }

    func clear() {
        todos.removeAll()
        saveTodos()
    }
}
