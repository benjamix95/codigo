import SwiftUI

@MainActor
final class TodoStore: ObservableObject {
    @Published var todos: [TodoItem] = [] {
        didSet {
            invalidateQueryCaches()
        }
    }
    @Published var filter: TodoFilter = .open
    let storageKey: String
    let userDefaults: UserDefaults
    var userVisibleTodosCache: [TodoItem]?
    var displayTodosCacheByConversationKey: [String: [TodoItem]] = [:]

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

    func cachedUserVisibleTodos() -> [TodoItem] {
        if let cached = userVisibleTodosCache {
            return cached
        }
        let visible = todos.filter { !$0.isOperationalPlaceholder }
        userVisibleTodosCache = visible
        return visible
    }

    func cachedDisplayTodosKey(for conversationId: UUID?) -> String {
        conversationId?.uuidString.lowercased() ?? "global"
    }

    func invalidateQueryCaches() {
        userVisibleTodosCache = nil
        displayTodosCacheByConversationKey.removeAll(keepingCapacity: true)
    }
}
