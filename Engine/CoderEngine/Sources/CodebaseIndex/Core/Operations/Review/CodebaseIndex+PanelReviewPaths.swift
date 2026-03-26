import Foundation

extension CodebaseIndex {
    /// Raccoglie path relativi per il panel review in **una sola** transizione actor (evita migliaia di `await` dal chiamante).
    /// Comportamento equivalente al vecchio loop `allIndexedFilePaths` + `getFileNode` + filtro sorgente.
    public func gatherSourcePathsForPanelReview(
        promptCap: Int,
        auditCap: Int
    ) -> (promptPaths: [String], workspaceIncludedPaths: [String]) {
        let take = max(0, auditCap)
        guard take > 0 else { return ([], []) }

        var indexedSources: [String] = []
        indexedSources.reserveCapacity(min(take, indexedFiles.count))
        for rel in indexedFiles.keys.sorted() {
            guard indexedSources.count < take else { break }
            if let node = allFileNodes[rel] {
                guard node.isSourceFile else { continue }
            }
            indexedSources.append(rel)
        }
        guard !indexedSources.isEmpty else { return ([], []) }

        let pCap = max(0, promptCap)
        let promptPaths = Array(indexedSources.prefix(pCap))
        return (promptPaths, indexedSources)
    }
}
