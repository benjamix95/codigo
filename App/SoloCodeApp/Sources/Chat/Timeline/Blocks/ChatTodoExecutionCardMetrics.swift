import Foundation

struct ChatTodoExecutionCardMetrics: Equatable {
    let doneCount: Int
    let totalCount: Int
    let fileCount: Int
    let linesAdded: Int
    let linesRemoved: Int

    static func build(items: [TodoItem], fileChanges: [ToolTraceFileChange]) -> ChatTodoExecutionCardMetrics {
        let doneCount = items.filter { $0.status == .done }.count
        let fileCount = fileChanges.count
        let linesAdded = fileChanges.reduce(0) { $0 + max(0, $1.added) }
        let linesRemoved = fileChanges.reduce(0) { $0 + max(0, $1.removed) }
        return ChatTodoExecutionCardMetrics(
            doneCount: doneCount,
            totalCount: items.count,
            fileCount: fileCount,
            linesAdded: linesAdded,
            linesRemoved: linesRemoved
        )
    }

    static func shouldStartExpanded(items: [TodoItem]) -> Bool {
        items.contains { $0.status == .inProgress || $0.status == .blocked }
    }
}
