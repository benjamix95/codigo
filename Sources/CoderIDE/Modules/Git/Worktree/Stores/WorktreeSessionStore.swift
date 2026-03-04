import Foundation
import SwiftUI

private let worktreeSessionsDefaultsKey = "CoderIDE.worktreeSessions.v1"

@MainActor
final class WorktreeSessionStore: ObservableObject {
    static let shared = WorktreeSessionStore()

    @Published private(set) var sessions: [UUID: WorktreeSession] = [:]

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        load()
    }

    func session(for conversationId: UUID?) -> WorktreeSession? {
        guard let conversationId else { return nil }
        return sessions[conversationId]
    }

    func upsert(_ session: WorktreeSession) {
        var updated = session
        updated.lastUpdatedAt = .now
        sessions[session.conversationId] = updated
        save()
    }

    func remove(conversationId: UUID?) {
        guard let conversationId else { return }
        sessions.removeValue(forKey: conversationId)
        save()
    }

    func isInWorktree(conversationId: UUID?, currentPath: String?) -> Bool {
        guard let session = session(for: conversationId),
              let currentPath else { return false }
        return normalized(currentPath).hasPrefix(normalized(session.worktreePath))
    }

    func isInLocal(conversationId: UUID?, currentPath: String?) -> Bool {
        guard let session = session(for: conversationId),
              let currentPath else { return false }
        return normalized(currentPath).hasPrefix(normalized(session.localRootPath))
    }

    private func load() {
        guard let data = userDefaults.data(forKey: worktreeSessionsDefaultsKey) else {
            sessions = [:]
            return
        }
        guard let decoded = try? JSONDecoder().decode([UUID: WorktreeSession].self, from: data) else {
            sessions = [:]
            return
        }
        sessions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        userDefaults.set(data, forKey: worktreeSessionsDefaultsKey)
    }

    private func normalized(_ path: String) -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let value = url.path(percentEncoded: false)
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }
}
