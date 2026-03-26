import Foundation

extension CodeReviewPanelStore {
    /// Cap file sorgente indicizzati per `WorkspaceContext.includedPaths` (audit swarm) — una passata condivisa col prompt.
    private static let codebaseAuditIncludedPathsCap = 12_000

    private func promptCap(for depth: ReviewScanDepth) -> Int {
        switch depth {
        case .fast: 96
        case .standard: 480
        case .pro: 8_000
        }
    }

    /// Una sola passata sull’indice: path per prompt (cap da depth) e set più ampio per audit/includedPaths.
    func gatherCodebaseIndexedPathsForRun(depth: ReviewScanDepth) async -> (
        promptPaths: [String],
        workspaceIncludedPaths: [String]
    ) {
        let index = workspaceStore.codebaseIndex
        let promptCap = promptCap(for: depth)
        let auditCap = max(promptCap, Self.codebaseAuditIncludedPathsCap)

        let paths = await index.allIndexedFilePaths().sorted()
        guard !paths.isEmpty else { return ([], []) }

        var indexedSources: [String] = []
        indexedSources.reserveCapacity(min(auditCap, paths.count))
        for rel in paths {
            guard indexedSources.count < auditCap else { break }
            if let node = await index.getFileNode(rel) {
                guard node.isSourceFile else { continue }
            }
            indexedSources.append(rel)
        }

        let workspaceIncludedPaths = indexedSources
        let promptPaths = Array(indexedSources.prefix(promptCap))
        return (promptPaths, workspaceIncludedPaths)
    }

    /// Percorsi relativi dall’indice da allegare al prompt (solo scope codebase; cap in base a `ReviewScanDepth`).
    func gatherCodebasePromptFilePaths(scope: ReviewScopeTarget, depth: ReviewScanDepth) async -> [String] {
        guard case .codebase = scope else { return [] }
        let split = await gatherCodebaseIndexedPathsForRun(depth: depth)
        return split.promptPaths
    }
}
