import SwiftUI
import CoderEngine

private let workspacesKey = "CoderIDE.workspaces"
private let activeWorkspaceIdKey = "CoderIDE.activeWorkspaceId"

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var workspaces: [Workspace] = []
    @Published var activeWorkspaceId: UUID?

    init() {
        load()
    }

    var activeWorkspace: Workspace? {
        guard let id = activeWorkspaceId else { return nil }
        return workspaces.first { $0.id == id }
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
    
    /// Crea workspace vuoto (senza cartelle)
    func createEmpty(name: String) {
        let ws = Workspace(name: name, folderPaths: [])
        workspaces.append(ws)
        if activeWorkspaceId == nil {
            activeWorkspaceId = ws.id
        }
        save()
    }

    /// Crea workspace con una cartella (convenienza)
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
        }
    }

    func removeExclusion(from workspaceId: UUID, path: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        workspaces[idx].excludedPaths.removeAll { $0 == path }
        save()
    }
}
