import Foundation

extension CodebaseIndex {
    struct IndexingTransaction {
        let operationName: String
        let startedAt: Date
        private(set) var isCompleted: Bool

        init(operationName: String, startedAt: Date = Date(), isCompleted: Bool = false) {
            self.operationName = operationName
            self.startedAt = startedAt
            self.isCompleted = isCompleted
        }

        mutating func markCompleted() {
            isCompleted = true
        }
    }

    func beginIndexingTransaction(operationName: String) -> IndexingTransaction {
        _status = .indexing
        isWorkspaceRebuildInProgress = true
        queuedRealtimeChanges.removeAll(keepingCapacity: true)
        return IndexingTransaction(operationName: operationName)
    }

    func finishIndexingTransaction(_ transaction: IndexingTransaction) {
        guard !transaction.isCompleted else { return }
        _indexingProgress = nil
        isWorkspaceRebuildInProgress = false
        queuedRealtimeChanges.removeAll(keepingCapacity: true)
        if _status == .indexing {
            _status = Task.isCancelled ? .idle : .error
        }
    }

    func refreshGitignoreRules() {
        if respectGitignore {
            gitignoreRules.removeAll()
            gitignoreRulesByRoot.removeAll()
            for root in currentWorkspacePaths {
                loadGitignoreRules(for: root)
            }
            return
        }
        gitignoreRules = []
        gitignoreRulesByRoot = [:]
    }

    func resetPrimaryIndexState() {
        fileTrees.removeAll()
        indexedFiles.removeAll()
        symbolsByName.removeAll()
        symbolsByFile.removeAll()
        symbolsByKind.removeAll()
        allFileNodes.removeAll()
        importGraph.removeAll()
        reverseImportGraph.removeAll()
        contentHashes.removeAll()
    }

    func rebuildWorkspaceFileTrees() {
        fileTrees.removeAll()
        allFileNodes.removeAll()
        for rootURL in currentWorkspacePaths {
            let tree = buildFileTree(
                at: rootURL,
                relativePath: "",
                depth: 0
            )
            fileTrees[rootURL.path] = tree
            flattenNodes(tree)
        }
    }
}
