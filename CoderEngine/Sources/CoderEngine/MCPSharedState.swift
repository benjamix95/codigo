import Foundation

/// Cross-process shared state for MCP server ↔ IDE communication.
/// The MCP server (separate process) reads/writes todo and plan state via a
/// well-known JSON file on disk. The main IDE app writes authoritative state
/// here on every save; the MCP server reads it for `todo_read` and writes
/// incremental updates for `todo_write` / `plan_step_update`.
public enum MCPSharedState {

    // MARK: - Paths

    private static let sharedDirectoryName = "mcp-shared"

    public static var sharedDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("CoderIDE")
            .appendingPathComponent(sharedDirectoryName)
    }

    public static var todosFilePath: URL {
        sharedDirectory.appendingPathComponent("todos.json")
    }

    // MARK: - Todos

    /// Write the full todo list (authoritative). Called by the main IDE app.
    public static func writeTodos(_ items: [[String: Any]]) {
        ensureDirectory()
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: todosFilePath, options: .atomic)
    }

    /// Read the current todo list. Called by the MCP server for `todo_read`.
    public static func readTodos() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: todosFilePath),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array
    }

    /// Append / upsert a single todo item from the MCP server side.
    /// The MCP server writes here; the IDE will overwrite with authoritative
    /// state on its next save cycle.
    public static func upsertTodoFromMCP(title: String, status: String?, priority: String?, notes: String?, activeForm: String? = nil, linkedFiles: [String]? = nil) {
        var todos = readTodos()
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }

        if let idx = todos.firstIndex(where: {
            ($0["title"] as? String)?.caseInsensitiveCompare(normalizedTitle) == .orderedSame
        }) {
            if let status { todos[idx]["status"] = status }
            if let priority { todos[idx]["priority"] = priority }
            if let notes, !notes.isEmpty { todos[idx]["notes"] = notes }
            if let activeForm, !activeForm.isEmpty { todos[idx]["activeForm"] = activeForm }
            if let linkedFiles, !linkedFiles.isEmpty { todos[idx]["linkedFiles"] = linkedFiles }
            todos[idx]["updatedAt"] = ISO8601DateFormatter().string(from: .now)
        } else {
            let item: [String: Any] = [
                "id": UUID().uuidString,
                "title": normalizedTitle,
                "status": status ?? "pending",
                "priority": priority ?? "medium",
                "source": "agent",
                "createdAt": ISO8601DateFormatter().string(from: .now),
                "updatedAt": ISO8601DateFormatter().string(from: .now),
                "notes": notes ?? "",
                "activeForm": activeForm ?? "",
                "linkedFiles": linkedFiles ?? [],
                "isPlanCanonical": false,
            ]
            todos.append(item)
        }
        writeTodos(todos)
    }

    /// Batch-write todos from the MCP server (full replacement of todos_json).
    public static func batchWriteTodosFromMCP(_ todosArray: [[String: Any]]) {
        var existing = readTodos()
        for todoItem in todosArray {
            let content = (todoItem["content"] as? String ?? todoItem["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !content.isEmpty else { continue }
            let status = todoItem["status"] as? String ?? "pending"

            if let idx = existing.firstIndex(where: {
                ($0["title"] as? String)?.caseInsensitiveCompare(content) == .orderedSame
            }) {
                existing[idx]["status"] = status
                if let activeForm = todoItem["activeForm"] as? String, !activeForm.isEmpty {
                    existing[idx]["activeForm"] = activeForm
                }
                if let notes = todoItem["notes"] as? String, !notes.isEmpty {
                    existing[idx]["notes"] = notes
                }
                if let files = todoItem["linkedFiles"] as? [String], !files.isEmpty {
                    existing[idx]["linkedFiles"] = files
                }
                if let priority = todoItem["priority"] as? String, !priority.isEmpty {
                    existing[idx]["priority"] = priority
                }
                existing[idx]["updatedAt"] = ISO8601DateFormatter().string(from: .now)
            } else {
                existing.append([
                    "id": UUID().uuidString,
                    "title": content,
                    "status": status,
                    "priority": (todoItem["priority"] as? String) ?? "medium",
                    "source": "agent",
                    "createdAt": ISO8601DateFormatter().string(from: .now),
                    "updatedAt": ISO8601DateFormatter().string(from: .now),
                    "notes": (todoItem["notes"] as? String) ?? "",
                    "activeForm": (todoItem["activeForm"] as? String) ?? "",
                    "linkedFiles": (todoItem["linkedFiles"] as? [String]) ?? [],
                    "isPlanCanonical": false,
                ])
            }
        }
        writeTodos(existing)
    }

    // MARK: - Helpers

    private static func ensureDirectory() {
        let dir = sharedDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
