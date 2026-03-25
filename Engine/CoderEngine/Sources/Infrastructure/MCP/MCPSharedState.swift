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

    /// Serial queue per garantire atomicità delle operazioni read-modify-write su disco.
    static let fileAccessQueue = DispatchQueue(label: "CoderEngine.MCPSharedState.FileAccess")

    /// Thread-safe tracker per chiavi di warning già emesse. Lock e stato co-locati.
    private static let legacyWarnings = LegacyWarningTracker()

    private final class LegacyWarningTracker: @unchecked Sendable {
        private let queue = DispatchQueue(label: "CoderEngine.MCPSharedState.LegacyWarnings")
        private var emittedKeys: Set<String> = []

        /// Returns true se la key è stata inserita per la prima volta (= non era già presente).
        func insertIfNew(_ key: String) -> Bool {
            queue.sync {
                emittedKeys.insert(key).inserted
            }
        }
    }

    // MARK: - Todos

    /// Write the full todo list (authoritative). Called by the main IDE app.
    /// Thread-safe: serialized through `fileAccessQueue` to prevent concurrent read/write races.
    public static func writeTodos(_ items: [[String: Any]]) {
        fileAccessQueue.sync {
            withTodosAdvisoryLock {
                _writeTodosUnsafe(items)
            }
        }
    }

    /// Internal write without queue protection — caller must already be inside `fileAccessQueue.sync`.
    private static func _writeTodosUnsafe(_ items: [[String: Any]]) {
        ensureDirectory()
        let canonical = canonicalizedTodos(items, defaultSource: "ide")
        guard let data = try? JSONSerialization.data(withJSONObject: canonical, options: [.prettyPrinted, .sortedKeys]) else {
            print("[MCPSharedState] ⚠️ Failed to serialize todos to JSON")
            return
        }
        do {
            try data.write(to: todosFilePath, options: .atomic)
        } catch {
            print("[MCPSharedState] ⚠️ Failed to write todos file: \(error.localizedDescription)")
        }
    }

    /// Normalize common LLM status aliases to canonical TodoStatus raw values.
    private static func normalizeStatus(_ raw: String?) -> String {
        guard let raw else { return "pending" }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
        switch normalized {
        case "pending", "in_progress", "done", "blocked": return normalized
        case "completed", "complete", "finished": return "done"
        case "running", "active", "doing", "started": return "in_progress"
        case "todo", "open", "queued", "waiting": return "pending"
        case "failed", "error", "stuck": return "blocked"
        case "cancelled", "canceled", "aborted", "skipped": return "blocked"
        default: return "pending"
        }
    }

    /// Read the current todo list. Called by the MCP server for `todo_read`.
    /// Thread-safe: serialized through `fileAccessQueue` to prevent torn reads during concurrent writes.
    public static func readTodos() -> [[String: Any]] {
        fileAccessQueue.sync {
            withTodosAdvisoryLock {
                _readTodosUnsafe()
            }
        }
    }

    /// Internal read without queue protection — caller must already be inside `fileAccessQueue.sync`.
    private static func _readTodosUnsafe() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: todosFilePath),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return canonicalizedTodos(array, defaultSource: "agent")
    }

    /// Append / upsert a single todo item from the MCP server side.
    /// The MCP server writes here; the IDE will overwrite with authoritative
    /// state on its next save cycle.
    public static func upsertTodoFromMCP(
        title: String,
        status: String?,
        priority: String?,
        notes: String?,
        activeForm: String? = nil,
        linkedFiles: [String]? = nil,
        sourceServer: String? = nil
    ) {
        fileAccessQueue.sync {
            withTodosAdvisoryLock {
            var todos = _readTodosUnsafe()
            let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedTitle.isEmpty else { return }

            if let idx = todos.firstIndex(where: {
                ($0["title"] as? String)?.caseInsensitiveCompare(normalizedTitle) == .orderedSame
            }) {
                logLegacyWarningOnce(
                    key: "upsert|\(normalizedTitle.lowercased())",
                    message: "[MCPSharedState] ⚠️ Legacy todo upsert matched by title (no id provided): '\(normalizedTitle)'"
                )
                if let status { todos[idx]["status"] = normalizeStatus(status) }
                if let priority { todos[idx]["priority"] = priority }
                if let notes, !notes.isEmpty { todos[idx]["notes"] = notes }
                if let activeForm, !activeForm.isEmpty { todos[idx]["activeForm"] = activeForm }
                if let linkedFiles, !linkedFiles.isEmpty { todos[idx]["linkedFiles"] = linkedFiles }
                todos[idx]["updatedAt"] = ISO8601DateFormatter().string(from: .now)
            } else {
                let source = sourceServer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let item: [String: Any] = [
                    "id": UUID().uuidString,
                    "title": normalizedTitle,
                    "status": normalizeStatus(status),
                    "priority": priority ?? "medium",
                    "source": source.isEmpty ? "agent" : source,
                    "createdAt": ISO8601DateFormatter().string(from: .now),
                    "updatedAt": ISO8601DateFormatter().string(from: .now),
                    "notes": notes ?? "",
                    "activeForm": activeForm ?? "",
                    "linkedFiles": linkedFiles ?? [],
                    "isPlanCanonical": false,
                ]
                todos.append(item)
            }
            _writeTodosUnsafe(todos)
            }
        }
    }

    /// Batch-write todos from the MCP server (full replacement of todos_json).
    public static func batchWriteTodosFromMCP(_ todosArray: [[String: Any]]) {
        fileAccessQueue.sync {
            withTodosAdvisoryLock {
            var existing = _readTodosUnsafe()
            for todoItem in todosArray {
                guard var canonicalItem = canonicalTodo(todoItem, defaultSource: "agent") else { continue }
                let hasProvidedID = providedTodoID(in: todoItem) != nil
                let id = (canonicalItem["id"] as? String) ?? UUID().uuidString
                canonicalItem["id"] = id

                if let idIndex = existing.firstIndex(where: {
                    (($0["id"] as? String) ?? "").caseInsensitiveCompare(id) == .orderedSame
                }) {
                    mergeTodoFields(from: canonicalItem, into: &existing[idIndex])
                    continue
                }

                if !hasProvidedID {
                    let content = (canonicalItem["title"] as? String ?? "")
                    if let titleIndex = existing.firstIndex(where: {
                        (($0["title"] as? String) ?? "").caseInsensitiveCompare(content) == .orderedSame
                    }) {
                        logLegacyWarningOnce(
                            key: "batch|\(content.lowercased())",
                            message: "[MCPSharedState] ⚠️ Legacy batch merge matched by title (id missing/new): '\(content)'"
                        )
                        mergeTodoFields(from: canonicalItem, into: &existing[titleIndex])
                        continue
                    }
                }

                existing.append(canonicalItem)
            }
            _writeTodosUnsafe(canonicalizedTodos(existing, defaultSource: "agent"))
            }
        }
    }

    // MARK: - Helpers

    private static func canonicalizedTodos(_ items: [[String: Any]], defaultSource: String) -> [[String: Any]] {
        var byID: [String: [String: Any]] = [:]
        var idOrder: [String] = []
        var legacyTitleIndex: [String: String] = [:]

        for raw in items {
            let hasProvidedID = providedTodoID(in: raw) != nil
            guard var item = canonicalTodo(raw, defaultSource: defaultSource) else { continue }
            let id = (item["id"] as? String) ?? UUID().uuidString
            item["id"] = id
            let title = ((item["title"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let existingID: String? = {
                if byID[id] != nil { return id }
                if !hasProvidedID { return legacyTitleIndex[title] }
                return nil
            }()
            if let existingID, let existing = byID[existingID] {
                var merged = existing
                mergeTodoFields(from: item, into: &merged)
                byID[existingID] = merged
                if existingID != id {
                    logLegacyWarningOnce(
                        key: "canonicalize|\(title)",
                        message: "[MCPSharedState] ⚠️ Legacy dedupe matched by title '\(title)' (missing/shared id)."
                    )
                }
                continue
            }

            byID[id] = item
            idOrder.append(id)
            if !hasProvidedID {
                legacyTitleIndex[title] = id
            }
        }

        return idOrder.compactMap { byID[$0] }
    }

    private static func canonicalTodo(_ raw: [String: Any], defaultSource: String) -> [String: Any]? {
        let title = (raw["title"] as? String ?? raw["content"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let now = ISO8601DateFormatter().string(from: .now)
        let id = (raw["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveID: String = {
            if let id, !id.isEmpty { return id }
            return UUID().uuidString
        }()
        let createdAt = normalizeTimestamp(raw["createdAt"] as? String) ?? now
        let updatedAt = normalizeTimestamp(raw["updatedAt"] as? String) ?? now
        let sourceRaw = (raw["source"] as? String ?? defaultSource).trimmingCharacters(in: .whitespacesAndNewlines)
        let source = sourceRaw.isEmpty ? defaultSource : sourceRaw
        let linkedFilesRaw = (raw["linkedFiles"] as? [String]) ?? (raw["files"] as? [String]) ?? []
        let linkedFiles = Array(Set(linkedFilesRaw.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
        let planConversationId: String? = {
            let raw = (raw["planConversationId"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let raw, !raw.isEmpty, UUID(uuidString: raw) != nil else { return nil }
            return raw
        }()

        var canonical: [String: Any] = [
            "id": effectiveID,
            "title": title,
            "status": normalizeStatus(raw["status"] as? String),
            "priority": normalizePriority(raw["priority"] as? String),
            "source": source,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "notes": (raw["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            "activeForm": (raw["activeForm"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            "linkedFiles": linkedFiles,
            "isPlanCanonical": (raw["isPlanCanonical"] as? Bool) ?? false,
        ]
        if let planConversationId {
            canonical["planConversationId"] = planConversationId
        }
        return canonical
    }

    private static func providedTodoID(in raw: [String: Any]) -> String? {
        let trimmed = (raw["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func logLegacyWarningOnce(key: String, message: String) {
        if legacyWarnings.insertIfNew(key) {
            print(message)
        }
    }

    private static func mergeTodoFields(from incoming: [String: Any], into target: inout [String: Any]) {
        if let status = incoming["status"] as? String { target["status"] = normalizeStatus(status) }
        if let priority = incoming["priority"] as? String { target["priority"] = normalizePriority(priority) }
        if let notes = incoming["notes"] as? String { target["notes"] = notes }
        if let activeForm = incoming["activeForm"] as? String { target["activeForm"] = activeForm }
        if let files = incoming["linkedFiles"] as? [String] { target["linkedFiles"] = files }
        if let source = incoming["source"] as? String, !source.isEmpty { target["source"] = source }
        if let planConversationId = incoming["planConversationId"] as? String,
           UUID(uuidString: planConversationId) != nil {
            target["planConversationId"] = planConversationId
        }
        if let createdAt = incoming["createdAt"] as? String, !createdAt.isEmpty {
            target["createdAt"] = normalizeTimestamp(createdAt) ?? createdAt
        } else if target["createdAt"] == nil {
            target["createdAt"] = ISO8601DateFormatter().string(from: .now)
        }
        target["updatedAt"] = normalizeTimestamp(incoming["updatedAt"] as? String)
            ?? ISO8601DateFormatter().string(from: .now)
    }

    private static func normalizePriority(_ raw: String?) -> String {
        guard let raw else { return "medium" }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "low", "medium", "high":
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        default:
            return "medium"
        }
    }

    private static func normalizeTimestamp(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        if let parsed = formatter.date(from: trimmed) {
            return formatter.string(from: parsed)
        }
        return nil
    }

    public static func ensureDirectory() {
        let fm = FileManager.default
        let dir = sharedDirectory
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let codeReviewDir = codeReviewDirectoryPath
        if !fm.fileExists(atPath: codeReviewDir.path) {
            try? fm.createDirectory(at: codeReviewDir, withIntermediateDirectories: true)
        }
    }
}
