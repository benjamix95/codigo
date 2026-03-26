import Foundation

/// Testo compatto "i/n" per la card thread nella sidebar, allineato a `TodoStore.displayTodosForChat`.
enum SidebarThreadTodoCaption {
    /// Indice 1-based del todo corrente (in corso o prossimo aperto) sul totale voci in coda per quel thread.
    static func progressLabel(displayTodos: [TodoItem]) -> String? {
        guard !displayTodos.isEmpty else { return nil }
        let hasOpen = displayTodos.contains { $0.status != .done }
        guard hasOpen else { return nil }

        let total = displayTodos.count
        if let idx = displayTodos.firstIndex(where: { $0.status == .inProgress }) {
            return "\(idx + 1)/\(total)"
        }
        if let idx = displayTodos.firstIndex(where: { $0.status != .done }) {
            return "\(idx + 1)/\(total)"
        }
        return nil
    }
}
