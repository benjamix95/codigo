import Foundation
import CoderEngine

@MainActor
extension WorkspaceStore {
    /// Keep workspace runtime state aligned with the selected project context.
    /// This guarantees codebase indexing also works for single-project contexts.
    func syncActiveWorkspace(with context: ProjectContext?) {
        guard let context else {
            setActive(id: nil)
            return
        }

        let normalizedFolderPaths = normalizeContextFolderPaths(context.folderPaths)
        guard !normalizedFolderPaths.isEmpty else {
            setActive(id: nil)
            return
        }

        let desiredWorkspace = Workspace(
            id: context.id,
            name: context.name,
            folderPaths: normalizedFolderPaths,
            excludedPaths: context.excludedPaths
        )

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

    private func normalizeContextFolderPaths(_ rawPaths: [String]) -> [String] {
        var seen = Set<String>()
        return rawPaths
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}
