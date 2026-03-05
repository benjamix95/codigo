import Foundation

extension EventNormalizer {
    static func normalizeTodoWrite(payload: [String: String], timestamp: Date) -> [NormalizedEvent]? {
        var events: [NormalizedEvent] = []

        if let todosJson = payload["todos_json"] ?? payload["todos"],
           let todosData = todosJson.data(using: .utf8),
           let todosArray = try? JSONSerialization.jsonObject(with: todosData) as? [[String: Any]] {
            var summaryParts: [String] = []
            for todoItem in todosArray {
                let content = (
                    todoItem["content"] as? String
                        ?? todoItem["title"] as? String
                )?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !content.isEmpty else { continue }
                let status = normalizedTodoStatus(todoItem["status"] as? String)
                var activeForm = (
                    (todoItem["activeForm"] as? String)
                        ?? (todoItem["active_form"] as? String)
                )?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Reject nested JSON objects accidentally passed as activeForm
                if let af = activeForm, af.hasPrefix("{") || af.hasPrefix("[") {
                    activeForm = nil
                }
                let priority = normalizedTodoPriority(todoItem["priority"] as? String)
                let notes = (todoItem["notes"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let linkedFiles = parseTodoLinkedFiles(todoItem)
                events.append(.todoWrite(TodoWritePayload(
                    id: nil,
                    title: content,
                    status: status,
                    priority: priority,
                    notes: notes,
                    activeForm: activeForm,
                    files: linkedFiles
                )))
                summaryParts.append(content)
            }
            if !events.isEmpty {
                let detail = "\(summaryParts.count) tasks"
                events.append(
                    .taskActivity(
                        TaskActivity(
                            type: "todo_write",
                            title: "Todo updated",
                            detail: detail,
                            payload: payload,
                            timestamp: timestamp,
                            phase: .planning,
                            isRunning: false
                        )
                    )
                )
                return events
            }
        }

        guard let todo = parseTodoWrite(payload: payload) else { return nil }
        let detail: String = {
            if todo.title == todoClearMarkerTitle {
                return "Todo list cleared"
            }
            return todo.title
        }()
        return [
            .todoWrite(todo),
            .taskActivity(TaskActivity(
                type: "todo_write",
                title: "Todo updated",
                detail: detail,
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: false
            ))
        ]
    }

    static func normalizeTodoRead(timestamp: Date) -> [NormalizedEvent] {
        return [
            .todoRead,
            .taskActivity(TaskActivity(
                type: "todo_read",
                title: "Todo read",
                detail: "Requested current task status",
                payload: ["todo_read": "true"],
                timestamp: timestamp,
                phase: .planning,
                isRunning: false
            ))
        ]
    }

    private static func parseTodoLinkedFiles(_ todoItem: [String: Any]) -> [String] {
        if let linked = todoItem["linkedFiles"] as? [String] {
            return linked.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let linked = todoItem["linked_files"] as? [String] {
            return linked.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let files = todoItem["files"] as? [String] {
            return files.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let raw = todoItem["linkedFiles"] as? String {
            return normalizeFileList(from: ["linkedFiles": raw])
        }
        if let raw = todoItem["linked_files"] as? String {
            return normalizeFileList(from: ["linked_files": raw])
        }
        if let raw = todoItem["files"] as? String {
            return normalizeFileList(from: ["files": raw])
        }
        return []
    }
}
