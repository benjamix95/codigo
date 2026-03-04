import Foundation
import CoderEngine

private let projectContextsKey = "CoderIDE.projectContexts"
private let activeContextIdKey = "CoderIDE.activeContextId"
private let lastActiveConversationKey = "CoderIDE.lastActiveConversationByContext"

@MainActor
final class ProjectContextStore: ObservableObject {
    @Published var contexts: [ProjectContext] = []
    @Published var activeContextId: UUID? {
        didSet { persistActiveContextId() }
    }

    init() {
        load()
    }

    private func persistActiveContextId() {
        if let activeContextId {
            UserDefaults.standard.set(activeContextId.uuidString, forKey: activeContextIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeContextIdKey)
        }
    }

    var activeContext: ProjectContext? {
        guard let activeContextId else { return nil }
        return contexts.first { $0.id == activeContextId }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: projectContextsKey),
           let decoded = try? JSONDecoder().decode([ProjectContext].self, from: data) {
            contexts = decoded
        }
        if let idString = UserDefaults.standard.string(forKey: activeContextIdKey),
           let id = UUID(uuidString: idString),
           contexts.contains(where: { $0.id == id }) {
            activeContextId = id
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(contexts) {
            UserDefaults.standard.set(data, forKey: projectContextsKey)
        }
        if let activeContextId {
            UserDefaults.standard.set(activeContextId.uuidString, forKey: activeContextIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeContextIdKey)
        }
    }

    func context(id: UUID?) -> ProjectContext? {
        guard let id else { return nil }
        return contexts.first { $0.id == id }
    }

    func upsert(_ context: ProjectContext) {
        if let idx = contexts.firstIndex(where: { $0.id == context.id }) {
            contexts[idx] = context
        } else {
            contexts.append(context)
        }
        save()
    }

    func remove(id: UUID) {
        contexts.removeAll { $0.id == id }
        if activeContextId == id {
            // Fall back to another context, or nil if none remain.
            activeContextId = contexts.first?.id ?? nil
        }
        clearLastActiveEntries(forContextId: id)
        save()
    }

    func ensureWorkspaceContexts(_ workspaces: [Workspace]) {
        for workspace in workspaces {
            var context = ProjectContext.fromWorkspace(workspace)
            if let existing = contexts.first(where: { $0.id == workspace.id }) {
                context.createdAt = existing.createdAt
                let hasStructuralChange =
                    existing.name != context.name
                    || existing.folderPaths != context.folderPaths
                    || existing.excludedPaths != context.excludedPaths
                context.updatedAt = hasStructuralChange ? .now : existing.updatedAt
                context.lastActiveFolderPath = existing.lastActiveFolderPath ?? (workspace.folderPaths.isEmpty ? nil : workspace.folderPaths.first)
            }
            upsert(context)
        }
    }

    @discardableResult
    func createOrReuseSingleProject(paths: [String], suggestedName: String? = nil) -> UUID? {
        let normalized = normalize(paths: paths)
        guard !normalized.isEmpty else { return nil }
        if let existing = contexts.first(where: { $0.kind == .singleProject && Set($0.folderPaths) == Set(normalized) }) {
            return existing.id
        }

        let name: String
        if let suggestedName, !suggestedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = suggestedName
        } else if normalized.count == 1 {
            name = (normalized[0] as NSString).lastPathComponent
        } else {
            name = "Project (\(normalized.count) folders)"
        }

        let context = ProjectContext(
            kind: .singleProject,
            name: name,
            folderPaths: normalized,
            excludedPaths: [],
            isPinned: false,
            lastActiveFolderPath: normalized.first
        )
        contexts.append(context)
        save()
        return context.id
    }

    func setActiveRoot(contextId: UUID, rootPath: String) {
        guard let idx = contexts.firstIndex(where: { $0.id == contextId }) else { return }
        guard contexts[idx].folderPaths.contains(rootPath) else { return }
        contexts[idx].lastActiveFolderPath = rootPath
        contexts[idx].updatedAt = .now
        save()
    }

    func updateName(contextId: UUID, name: String) {
        guard let idx = contexts.firstIndex(where: { $0.id == contextId }) else { return }
        contexts[idx].name = name
        contexts[idx].updatedAt = .now
        save()
    }

    private func contextKey(contextId: UUID, folderPath: String?) -> String {
        "\(contextId.uuidString)|\(folderPath ?? "")"
    }

    func setLastActiveConversation(contextId: UUID, folderPath: String?, conversationId: UUID) {
        var map = loadLastActiveMap()
        map[contextKey(contextId: contextId, folderPath: folderPath)] = conversationId.uuidString
        saveLastActiveMap(map)
    }

    func lastActiveConversationId(contextId: UUID, folderPath: String?) -> UUID? {
        let map = loadLastActiveMap()
        guard let str = map[contextKey(contextId: contextId, folderPath: folderPath)],
              let id = UUID(uuidString: str) else { return nil }
        return id
    }

    /// Remove all lastActive entries for a given context (used when context is deleted).
    func clearLastActiveEntries(forContextId contextId: UUID) {
        var map = loadLastActiveMap()
        let prefix = contextId.uuidString + "|"
        map = map.filter { !$0.key.hasPrefix(prefix) }
        saveLastActiveMap(map)
    }

    /// Remove a specific conversation from the lastActive map (used when conversation is deleted).
    func clearLastActiveConversation(conversationId: UUID) {
        var map = loadLastActiveMap()
        let idStr = conversationId.uuidString
        map = map.filter { $0.value != idStr }
        saveLastActiveMap(map)
    }

    private func loadLastActiveMap() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: lastActiveConversationKey),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    private func saveLastActiveMap(_ map: [String: String]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: lastActiveConversationKey)
        }
    }

    private func normalize(paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }.filter { seen.insert($0).inserted }
    }
}
