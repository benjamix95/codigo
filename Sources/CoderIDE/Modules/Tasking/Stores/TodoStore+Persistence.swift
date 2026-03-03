import Foundation
import CoderEngine

extension TodoStore {
    func loadTodos() {
        guard let data = userDefaults.data(forKey: storageKey) else { return }
        do {
            todos = try JSONDecoder().decode([TodoItem].self, from: data)
        } catch {
            print("[TodoStore] ⚠️ Failed to decode todos: \(error.localizedDescription)")
        }
    }

    func saveTodos() {
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
    func syncToSharedState() {
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
}
