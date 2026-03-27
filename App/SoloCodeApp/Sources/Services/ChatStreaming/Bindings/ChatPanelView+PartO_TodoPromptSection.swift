import Foundation

func currentTodoPromptSectionText(for todos: [TodoItem]) -> String {
    guard !todos.isEmpty else { return "" }

    let todoSection = todos
        .map(todoLineForPrompt)
        .joined(separator: "\n")
    return "\n\n## Current todos\n\(todoSection)"
}

private func todoLineForPrompt(_ todo: TodoItem) -> String {
    let check = todo.status == .done ? "x" : " "
    let trimmedNotes = todo.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    let notesSuffix = trimmedNotes.isEmpty ? "" : " — \(trimmedNotes)"
    let linkedPreview = todo.linkedFiles.prefix(8)
    let linkedFilesSuffix: String
    if linkedPreview.isEmpty {
        linkedFilesSuffix = ""
    } else {
        let joined = linkedPreview.joined(separator: ", ")
        let overflow = todo.linkedFiles.count > linkedPreview.count ? ", ..." : ""
        linkedFilesSuffix = " [files: \(joined)\(overflow)]"
    }
    return "- [\(check)] \(todo.title) (\(todo.status.rawValue))\(notesSuffix)\(linkedFilesSuffix)"
}

extension ChatPanelView {
    func currentTodoPromptSection(for todos: [TodoItem]) -> String {
        currentTodoPromptSectionText(for: todos)
    }
}
