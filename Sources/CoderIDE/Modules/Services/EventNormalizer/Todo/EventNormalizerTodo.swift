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
                let activeForm = sanitizeTodoActiveForm(
                    (todoItem["activeForm"] as? String)
                        ?? (todoItem["active_form"] as? String)
                )
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
        let keys = ["linkedFiles", "linked_files", "files"]
        var merged: [String] = []
        for key in keys {
            merged.append(contentsOf: parseStringArray(rawValue: todoItem[key]))
        }

        var seen = Set<String>()
        return merged
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}
