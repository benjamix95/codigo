import Foundation

extension ProjectContextStore {
    var recentProjectContexts: [ProjectContext] {
        contexts
            .filter { $0.kind == .singleProject && !$0.folderPaths.isEmpty }
            .sorted(by: contextRecencySort)
    }

    var recentWorkspaceContexts: [ProjectContext] {
        contexts
            .filter { $0.kind == .workspace }
            .sorted(by: contextRecencySort)
    }

    func markAsRecentlyUsed(contextId: UUID?) {
        guard let contextId,
              let idx = contexts.firstIndex(where: { $0.id == contextId })
        else { return }
        contexts[idx].updatedAt = .now
        save()
    }

    private func contextRecencySort(_ lhs: ProjectContext, _ rhs: ProjectContext) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.createdAt > rhs.createdAt
    }
}
