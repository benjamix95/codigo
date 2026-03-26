import Foundation

extension CodeReviewPanelStore {
    /// Percorsi relativi dall’indice da allegare al prompt (solo scope codebase; cap in base a `ReviewScanDepth`).
    func gatherCodebasePromptFilePaths(scope: ReviewScopeTarget, depth: ReviewScanDepth) async -> [String] {
        guard case .codebase = scope else { return [] }
        let index = workspaceStore.codebaseIndex

        let cap: Int
        switch depth {
        case .fast: cap = 96
        case .standard: cap = 480
        case .pro: cap = 8_000
        }

        let paths = await index.allIndexedFilePaths().sorted()
        guard !paths.isEmpty else { return [] }

        var picked: [String] = []
        picked.reserveCapacity(min(cap, paths.count))
        for rel in paths {
            guard picked.count < cap else { break }
            if let node = await index.getFileNode(rel) {
                guard node.isSourceFile else { continue }
            }
            picked.append(rel)
        }
        return picked
    }
}
