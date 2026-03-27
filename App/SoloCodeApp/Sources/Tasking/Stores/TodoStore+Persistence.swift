import Foundation
import CoderEngine

extension TodoStore {
    private static let sharedStateSyncDebounceNs: UInt64 = 150_000_000

    func loadTodos() {
        guard let data = userDefaults.data(forKey: storageKey) else { return }
        do {
            todos = try JSONDecoder().decode([TodoItem].self, from: data)
            lastSavedVisibleTodosData = data
            var didClean = deduplicateCanonicalTodos()
            if deduplicateRuntimeTodosByTitle() { didClean = true }
            if didClean {
                saveTodos()
            }
        } catch {
            #if DEBUG
            print("[TodoStore] ⚠️ Failed to decode todos: \(error.localizedDescription)")
            #endif
        }
    }

    /// Removes duplicate runtime todos with the same title, keeping only the most recent one.
    /// This cleans up accumulated duplicates like "Review bug cluster" x 105.
    @discardableResult
    func deduplicateRuntimeTodosByTitle() -> Bool {
        var seenTitles: [String: Int] = [:] // title → index of newest
        var duplicateIndices: Set<Int> = []

        for (index, todo) in todos.enumerated() {
            guard !todo.isPlanCanonical else { continue }
            let key = todo.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            if let existingIndex = seenTitles[key] {
                let existing = todos[existingIndex]
                let todoIsNewer = todo.updatedAt > existing.updatedAt
                let tieBreakTodoWins =
                    todo.updatedAt == existing.updatedAt && todo.id.uuidString < existing.id.uuidString
                if todoIsNewer || tieBreakTodoWins {
                    todos[index].planConversationId =
                        todo.planConversationId ?? existing.planConversationId
                    todos[index].lastTouchedConversationId =
                        todo.lastTouchedConversationId ?? existing.lastTouchedConversationId
                    duplicateIndices.insert(existingIndex)
                    seenTitles[key] = index
                } else {
                    todos[existingIndex].planConversationId =
                        existing.planConversationId ?? todo.planConversationId
                    todos[existingIndex].lastTouchedConversationId =
                        existing.lastTouchedConversationId ?? todo.lastTouchedConversationId
                    duplicateIndices.insert(index)
                }
            } else {
                seenTitles[key] = index
            }
        }

        guard !duplicateIndices.isEmpty else { return false }
        let beforeCount = todos.count
        todos = todos.enumerated().filter { !duplicateIndices.contains($0.offset) }.map(\.element)
        let removed = beforeCount - todos.count
        #if DEBUG
        print("[TodoStore] Removed \(removed) duplicate runtime todos")
        #endif
        return true
    }

    static let maxTodoCount = 50

    func saveTodos() {
        if mutationBatchDepth > 0 {
            needsSaveAfterBatch = true
            return
        }
        trimExcessTodos()
        do {
            let visibleTodos = userVisibleTodos
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(visibleTodos)
            guard data != lastSavedVisibleTodosData else { return }
            userDefaults.set(data, forKey: storageKey)
            lastSavedVisibleTodosData = data
            scheduleSharedStateSync(visibleTodos: visibleTodos)
        } catch {
            #if DEBUG
            print("[TodoStore] ⚠️ Failed to encode todos: \(error.localizedDescription)")
            #endif
        }
    }

    /// Removes oldest completed/blocked todos when count exceeds the max limit.
    /// Keeps all open/in-progress todos and newest completed ones.
    private func trimExcessTodos() {
        let visibleCount = userVisibleTodos.count
        guard visibleCount > Self.maxTodoCount else { return }

        // Separate active (open/in-progress) from finished (done/blocked)
        let placeholders = todos.filter(\.isOperationalPlaceholder)
        let visible = userVisibleTodos
        let active = visible.filter { $0.status == .pending || $0.status == .inProgress }
        var finished = visible.filter { $0.status == .done || $0.status == .blocked }

        // Sort finished by updatedAt descending — keep newest
        finished.sort { $0.updatedAt > $1.updatedAt }

        let maxFinished = max(0, Self.maxTodoCount - active.count)
        let kept = finished.prefix(maxFinished)

        todos = placeholders + active + kept
    }

    /// Write current todos to the shared state file so the MCP server
    /// can serve them via `coderide_todo_read`.
    func syncToSharedState() {
        sharedStateSyncTask?.cancel()
        sharedStateSyncTask = nil
        syncToSharedState(visibleTodos: userVisibleTodos)
    }

    private func scheduleSharedStateSync(visibleTodos: [TodoItem]) {
        sharedStateSyncTask?.cancel()
        sharedStateSyncTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.sharedStateSyncDebounceNs)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.syncToSharedState(visibleTodos: visibleTodos)
            self.sharedStateSyncTask = nil
        }
    }

    private func syncToSharedState(visibleTodos: [TodoItem]) {
        let items: [[String: Any]] = visibleTodos.map { todo in
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
            if let lastTouchedConversationId = todo.lastTouchedConversationId {
                record["lastTouchedConversationId"] = lastTouchedConversationId.uuidString
            }
            if let planOrder = todo.planOrder {
                record["planOrder"] = planOrder
            }
            return record
        }
        MCPSharedState.writeTodos(items)
    }
}
