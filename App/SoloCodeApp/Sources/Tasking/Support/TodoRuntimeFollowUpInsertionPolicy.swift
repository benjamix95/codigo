import Foundation

/// I follow-up runtime non vengono inseriti implicitamente: devono arrivare
/// o dal piano canonico oppure da un `todo_write` esplicito del runtime.
enum TodoRuntimeFollowUpInsertionPolicy {
    static func implicitFollowUpTitles(
        in todos: [TodoItem],
        conversationId: UUID?
    ) -> [String] {
        _ = todos
        _ = conversationId
        return []
    }
}
