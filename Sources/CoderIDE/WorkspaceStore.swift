import SwiftUI
import CoderEngine

private let workspacesKey = "CoderIDE.workspaces"
private let activeWorkspaceIdKey = "CoderIDE.activeWorkspaceId"
private let codebaseIndexEnabledKey = "codebase_index_enabled"
private let codebaseIndexExcludedPathsKey = "codebase_index_excluded_paths"

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var workspaces: [Workspace] = []
    @Published var activeWorkspaceId: UUID?

    /// Shared codebase index — available to all providers
    let codebaseIndex = CodebaseIndex()

    /// File watcher for real-time index updates
    private var fileWatcher: FileWatcher?

    init() {
        load()
    }

    var activeWorkspace: Workspace? {
        guard let id = activeWorkspaceId else { return nil }
        return workspaces.first { $0.id == id }
    }

    /// Workspace folder URLs for the active workspace
    var activeWorkspacePaths: [URL] {
        guard let ws = activeWorkspace else { return [] }
        return ws.folderPaths.map { URL(fileURLWithPath: $0) }
    }

    /// Active workspace excluded paths
    var activeExcludedPaths: [String] {
        activeWorkspace?.excludedPaths ?? []
    }

    private var isAutomaticIndexingEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: codebaseIndexEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: codebaseIndexEnabledKey)
    }

    private var globalExcludedPaths: [String] {
        let raw = UserDefaults.standard.string(forKey: codebaseIndexExcludedPathsKey) ?? ""
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var effectiveExcludedPaths: [String] {
        var seen = Set<String>()
        let combined = activeExcludedPaths + globalExcludedPaths
        return combined.filter { seen.insert($0).inserted }
    }

    /// Index the active workspace (called on workspace change)
    func indexActiveWorkspace() {
        let paths = activeWorkspacePaths

        // Stop existing file watcher
        if let watcher = fileWatcher {
            Task { await watcher.stop() }
            fileWatcher = nil
        }

        guard isAutomaticIndexingEnabled, !paths.isEmpty else {
            let index = codebaseIndex
            Task.detached(priority: .utility) {
                await index.clear()
            }
            return
        }

        let excluded = effectiveExcludedPaths
        let index = codebaseIndex
        Task.detached(priority: .utility) {
            let _ = await index.indexWorkspace(paths: paths, excludedPaths: excluded)

            // Start file watcher for real-time updates
            let watcher = FileWatcher(index: index, workspacePaths: paths)
            await watcher.start()
            await MainActor.run { [weak self] in
                self?.fileWatcher = watcher
            }
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: workspacesKey),
           let decoded = try? JSONDecoder().decode([Workspace].self, from: data) {
            workspaces = decoded
        }
        if let idStr = UserDefaults.standard.string(forKey: activeWorkspaceIdKey),
           let id = UUID(uuidString: idStr) {
            activeWorkspaceId = workspaces.contains { $0.id == id } ? id : nil
        }
        indexActiveWorkspace()
    }

    func setActive(id: UUID?) {
        activeWorkspaceId = id
        save()
        indexActiveWorkspace()
    }

    func save() {
        if let data = try? JSONEncoder().encode(workspaces) {
            UserDefaults.standard.set(data, forKey: workspacesKey)
        }
        if let id = activeWorkspaceId {
            UserDefaults.standard.set(id.uuidString, forKey: activeWorkspaceIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeWorkspaceIdKey)
        }
    }
    
    /// Create an empty workspace (without folders)
    func createEmpty(name: String) {
        let ws = Workspace(name: name, folderPaths: [])
        workspaces.append(ws)
        if activeWorkspaceId == nil {
            activeWorkspaceId = ws.id
        }
        save()
    }

    /// Create a workspace with a single root folder (convenience)
    func create(name: String, rootPath: String) {
        let ws = Workspace(name: name, rootPath: rootPath)
        workspaces.append(ws)
        if activeWorkspaceId == nil {
            activeWorkspaceId = ws.id
        }
        save()
    }
    
    /// Aggiunge cartella al workspace
    func addFolder(to workspaceId: UUID, path: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        let pathNorm = path.hasSuffix("/") ? String(path.dropLast()) : path
        if !workspaces[idx].folderPaths.contains(pathNorm) {
            workspaces[idx].folderPaths.append(pathNorm)
            save()
            if workspaceId == activeWorkspaceId { indexActiveWorkspace() }
        }
    }
    
    /// Rimuove cartella dal workspace
    func removeFolder(from workspaceId: UUID, path: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        workspaces[idx].folderPaths.removeAll { $0 == path }
        save()
    }

    func update(_ workspace: Workspace) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces[idx] = workspace
        save()
        if workspace.id == activeWorkspaceId { indexActiveWorkspace() }
    }

    func delete(id: UUID) {
        workspaces.removeAll { $0.id == id }
        if activeWorkspaceId == id {
            activeWorkspaceId = workspaces.first?.id
        }
        save()
    }

    func addExclusion(to workspaceId: UUID, path: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        let pathNorm = path.hasSuffix("/") ? String(path.dropLast()) : path
        if !workspaces[idx].excludedPaths.contains(pathNorm) {
            workspaces[idx].excludedPaths.append(pathNorm)
            save()
            if workspaceId == activeWorkspaceId { indexActiveWorkspace() }
        }
    }

    func removeExclusion(from workspaceId: UUID, path: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        workspaces[idx].excludedPaths.removeAll { $0 == path }
        save()
        if workspaceId == activeWorkspaceId { indexActiveWorkspace() }
    }
}
