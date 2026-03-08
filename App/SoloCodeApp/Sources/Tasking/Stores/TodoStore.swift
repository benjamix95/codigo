import SwiftUI

@MainActor
final class TodoStore: ObservableObject {
    @Published var todos: [TodoItem] = []
    @Published var filter: TodoFilter = .open
    let storageKey: String
    let userDefaults: UserDefaults

    /// Callback invoked when a canonical todo's status changes, enabling plan board sync.
    var onCanonicalTodoStatusChange: ((String, TodoStatus, UUID?) -> Void)?

    init(
        storageKey: String = todosStorageKey,
        userDefaults: UserDefaults = .standard
    ) {
        self.storageKey = storageKey
        self.userDefaults = userDefaults
        loadTodos()
        syncToSharedState()
    }
}
