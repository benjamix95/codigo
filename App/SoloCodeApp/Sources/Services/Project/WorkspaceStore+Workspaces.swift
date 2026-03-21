import SwiftUI
import CoderEngine

extension WorkspaceStore {
    func createEmpty(name: String) {
        let ws = Workspace(name: name, folderPaths: [])
        workspaces.append(ws)
        if activeWorkspaceId == nil {
            activeWorkspaceId = ws.id
        }
        save()
    }

    func create(name: String, rootPath: String) {
        let ws = normalizedWorkspace(Workspace(name: name, rootPath: rootPath))
        workspaces.append(ws)
        if activeWorkspaceId == nil {
            activeWorkspaceId = ws.id
        }
        save()
    }

    func addFolder(to workspaceId: UUID, path: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        guard addNormalizedWorkspacePath(path, to: &workspaces[idx].folderPaths) else { return }
        save()
        if workspaceId == activeWorkspaceId { indexActiveWorkspace() }
    }

    func removeFolder(from workspaceId: UUID, path: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        guard removeNormalizedWorkspacePath(path, from: &workspaces[idx].folderPaths) else { return }
        save()
        if workspaceId == activeWorkspaceId { indexActiveWorkspace() }
    }

    func update(_ workspace: Workspace) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces[idx] = normalizedWorkspace(workspace)
        save()
        if workspace.id == activeWorkspaceId { indexActiveWorkspace() }
    }

    func delete(id: UUID) {
        let requestedId = id
        workspaces.removeAll { $0.id == id }

        let activeStillExists = activeWorkspaceId.flatMap { current in
            workspaces.contains { $0.id == current }
        } ?? false

        if activeWorkspaceId == requestedId || !activeStillExists {
            activeWorkspaceId = workspaces.first?.id
        }

        save()
        indexActiveWorkspace()
    }

    func addExclusion(to workspaceId: UUID, path: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        guard addNormalizedWorkspacePath(path, to: &workspaces[idx].excludedPaths) else { return }
        save()
        if workspaceId == activeWorkspaceId { indexActiveWorkspace() }
    }

    func removeExclusion(from workspaceId: UUID, path: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        guard removeNormalizedWorkspacePath(path, from: &workspaces[idx].excludedPaths) else { return }
        save()
        if workspaceId == activeWorkspaceId { indexActiveWorkspace() }
    }

    func syncActiveWorkspace(with context: ProjectContext?) {
        guard let context else {
            setActive(id: nil)
            return
        }

        let desiredWorkspace = normalizedWorkspace(
            Workspace(
                id: context.id,
                name: context.name,
                folderPaths: context.folderPaths,
                excludedPaths: context.excludedPaths
            )
        )
        guard !desiredWorkspace.folderPaths.isEmpty else {
            setActive(id: nil)
            return
        }

        if let existingIndex = workspaces.firstIndex(where: { $0.id == context.id }) {
            let existing = workspaces[existingIndex]
            if existing.name != desiredWorkspace.name
                || existing.folderPaths != desiredWorkspace.folderPaths
                || existing.excludedPaths != desiredWorkspace.excludedPaths {
                workspaces[existingIndex] = desiredWorkspace
                save()
            }
        } else {
            workspaces.append(desiredWorkspace)
            save()
        }

        setActive(id: context.id)
    }
}
