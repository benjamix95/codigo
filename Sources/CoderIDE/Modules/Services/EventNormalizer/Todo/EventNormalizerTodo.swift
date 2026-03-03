import Foundation

extension EventNormalizer {
    static func normalizeTodoWrite(payload: [String: String], timestamp: Date) -> [NormalizedEvent]? {
        var events: [NormalizedEvent] = []

        if let todosJson = payload["todos_json"] ?? payload["todos"],
           let todosData = todosJson.data(using: .utf8),
           let todosArray = try? JSONSerialization.jsonObject(with: todosData) as? [[String: Any]] {
            // Empty array is valid — means "clear todos" or "no-op"; skip batch processing
            guard !todosArray.isEmpty else {
                return events
            }
            var summaryParts: [String] = []
            for todoItem in todosArray {
                let content = (
                    todoItem["content"] as? String
                        ?? todoItem["title"] as? String
                )?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !content.isEmpty else { continue }
                let status = normalizedTodoStatus(todoItem["status"] as? String)
                var activeForm = (todoItem["activeForm"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Reject nested JSON objects accidentally passed as activeForm
                if let af = activeForm, af.hasPrefix("{") || af.hasPrefix("[") {
                    activeForm = nil
                }
                let priority = normalizedTodoPriority(todoItem["priority"] as? String)
                let notes = (todoItem["notes"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let linkedFiles = (todoItem["linkedFiles"] as? [String])
                    ?? (todoItem["files"] as? [String])
                    ?? []
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
        return [
            .todoWrite(todo),
            .taskActivity(TaskActivity(
                type: "todo_write",
                title: "Todo updated",
                detail: todo.title,
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
}
