import Foundation
import CoderEngine

private let conversationsStorageKey = "CoderIDE.conversations"
private let planBoardsStorageKey = "CoderIDE.planBoards"
private let draftsStorageKey = "CoderIDE.draftTexts"

private struct SendableUserDefaults: @unchecked Sendable {
    let value: UserDefaults
}

extension ChatStore {
func loadConversations() {
    guard let data = userDefaults.data(forKey: conversationsStorageKey) else {
        isAsyncConversationLoadPending = false
        return
    }

    if data.count < Self.asyncLoadThreshold {
        // Small dataset – decode synchronously (fast enough, avoids empty-flash).
        if let decoded = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = normalizeLoadedConversationsForColdStart(decoded)
        }
        isAsyncConversationLoadPending = false
        return
    }

    // Large dataset – decode on a background queue to avoid blocking the main thread.
    isAsyncConversationLoadPending = true
    Task.detached(priority: .userInitiated) {
        let decoded = try? JSONDecoder().decode([Conversation].self, from: data)
        await MainActor.run {
            // If a save happened while we were decoding, don't overwrite newer data.
            defer {
                self.isAsyncConversationLoadPending = false
                self.ensureDefaultConversationIfNeeded()
            }
            guard !self.hasSavedSinceLoad else { return }
            if let decoded, self.conversations.isEmpty {
                self.conversations = self.normalizeLoadedConversationsForColdStart(decoded)
            } else if let decoded, !decoded.isEmpty {
                // Merge: keep any in-memory conversations (even if empty)
                // and prepend disk-only conversations that aren't already loaded.
                let existingIds = Set(self.conversations.map(\.id))
                let loaded = self.normalizeLoadedConversationsForColdStart(decoded)
                    .filter { !existingIds.contains($0.id) }
                if !loaded.isEmpty {
                    self.conversations = loaded + self.conversations
                }
            }
        }
    }
}

func saveConversations() {
    hasSavedSinceLoad = true
    pendingSaveTask?.cancel()
    let snapshot = conversations
    pendingSaveTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled, let self else { return }
        let defaults = SendableUserDefaults(value: self.userDefaults)
        Self.persistQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            defaults.value.set(data, forKey: conversationsStorageKey)
        }
    }
}

/// Bypasses the 200ms debounce and writes to disk on the persist queue.
/// Uses async dispatch to avoid deadlocking the main thread — UserDefaults.set
/// can post NSUserDefaultsDidChangeNotification which synchronously dispatches
/// back to the main thread, causing a deadlock if we used dispatch_sync here.
func saveConversationsImmediately() {
    hasSavedSinceLoad = true
    pendingSaveTask?.cancel()
    pendingSaveTask = nil
    let snapshot = conversations
    let defaults = SendableUserDefaults(value: self.userDefaults)
    Self.persistQueue.async {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.value.set(data, forKey: conversationsStorageKey)
    }
}

func loadPlanBoards() {
    guard let data = userDefaults.data(forKey: planBoardsStorageKey) else { return }

    let decode: () -> [UUID: PlanBoard]? = {
        guard let decoded = try? JSONDecoder().decode([String: PlanBoard].self, from: data) else { return nil }
        return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value -> (UUID, PlanBoard)? in
            guard let uuid = UUID(uuidString: key) else { return nil }
            return (uuid, value)
        })
    }

    if data.count < Self.asyncLoadThreshold {
        if let boards = decode() {
            let conversationIds = Set(conversations.map(\.id))
            planBoards = conversationIds.isEmpty ? boards : boards.filter { conversationIds.contains($0.key) }
        }
        normalizeLoadedRustStoreSnapshot()
        return
    }

    Task.detached(priority: .userInitiated) {
        guard let boards = decode() else { return }
        await MainActor.run {
            let conversationIds = Set(self.conversations.map(\.id))
            let pruned = conversationIds.isEmpty ? boards : boards.filter { conversationIds.contains($0.key) }
            self.planBoards.merge(pruned) { existing, _ in existing }
            self.normalizeLoadedRustStoreSnapshot()
        }
    }
}

func savePlanBoards() {
    pendingPlanSaveTask?.cancel()
    let snapshot = planBoards
    pendingPlanSaveTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled, let self else { return }
        let serialized = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.key.uuidString, $0.value) })
        let defaults = SendableUserDefaults(value: self.userDefaults)
        Self.persistQueue.async {
            guard let data = try? JSONEncoder().encode(serialized) else { return }
            defaults.value.set(data, forKey: planBoardsStorageKey)
        }
    }
}

// MARK: - Draft Persistence

func loadDrafts() {
    guard let data = userDefaults.data(forKey: draftsStorageKey) else { return }
    guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
    draftTexts = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value -> (UUID, String)? in
        guard let uuid = UUID(uuidString: key) else { return nil }
        return (uuid, value)
    })
}

func saveDrafts() {
    pendingDraftSaveTask?.cancel()
    let snapshot = draftTexts
    pendingDraftSaveTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, let self else { return }
        let serialized = Dictionary(uniqueKeysWithValues: snapshot.map {
            ($0.key.uuidString.lowercased(), $0.value)
        })
        let defaults = SendableUserDefaults(value: self.userDefaults)
        Self.persistQueue.async {
            guard let data = try? JSONEncoder().encode(serialized) else { return }
            defaults.value.set(data, forKey: draftsStorageKey)
        }
    }
}

func saveDraftsImmediately() {
    pendingDraftSaveTask?.cancel()
    pendingDraftSaveTask = nil
    let snapshot = draftTexts
    let defaults = SendableUserDefaults(value: self.userDefaults)
    Self.persistQueue.async {
        let serialized = snapshot.reduce(into: [String: String]()) {
            $0[$1.key.uuidString.lowercased()] = $1.value
        }
        guard let data = try? JSONEncoder().encode(serialized) else { return }
        defaults.value.set(data, forKey: draftsStorageKey)
    }
}

func migrateLegacyContextsIfNeeded(contextStore: ProjectContextStore, workspaceStore: WorkspaceStore) {
    contextStore.ensureWorkspaceContexts(workspaceStore.workspaces)
    var changed = false
    for idx in conversations.indices {
        if conversations[idx].contextId == nil {
            if let workspaceId = conversations[idx].workspaceId {
                conversations[idx].contextId = workspaceId
                changed = true
            } else if !conversations[idx].adHocFolderPaths.isEmpty,
                      let contextId = contextStore.createOrReuseSingleProject(paths: conversations[idx].adHocFolderPaths) {
                conversations[idx].contextId = contextId
                changed = true
            }
        }
    }
    if changed { saveConversations() }
}
}
