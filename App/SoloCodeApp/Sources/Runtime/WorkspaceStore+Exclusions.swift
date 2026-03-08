import Foundation

@MainActor
extension WorkspaceStore {
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
}
