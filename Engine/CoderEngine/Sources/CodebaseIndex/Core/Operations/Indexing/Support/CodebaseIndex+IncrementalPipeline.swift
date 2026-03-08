import Foundation

extension CodebaseIndex {
    private enum IncrementalReindexAction {
        case unchanged(relativePath: String)
        case reindexed(relativePath: String, indexed: IndexedFile)
        case failed(relativePath: String)

        var relativePath: String {
            switch self {
            case .unchanged(let relativePath),
                 .reindexed(let relativePath, _),
                 .failed(let relativePath):
                return relativePath
            }
        }
    }

    struct IncrementalPipelineResult {
        let updatedCount: Int
        let failedReindexPaths: Set<String>
        let changedFiles: [IndexedFile]
        let wasCancelled: Bool
    }

    private static let incrementalChunkSize = 32

    func runIncrementalReindexPipeline(
        sourceNodes: [String: FileNode],
        startingProcessed: Int,
        totalToProcess: Int
    ) async -> IncrementalPipelineResult {
        let sortedEntries = sourceNodes.sorted { $0.key < $1.key }
        let hashSnapshot = contentHashes
        let indexedAtSnapshot = indexedFiles.mapValues(\.indexedAt)

        var changedFiles: [IndexedFile] = []
        var failedReindexPaths: Set<String> = []
        var updatedCount = 0
        var processed = startingProcessed

        for batchStart in stride(from: 0, to: sortedEntries.count, by: Self.incrementalChunkSize) {
            if Task.isCancelled {
                return IncrementalPipelineResult(
                    updatedCount: updatedCount,
                    failedReindexPaths: failedReindexPaths,
                    changedFiles: changedFiles,
                    wasCancelled: true
                )
            }

            let batchEnd = min(batchStart + Self.incrementalChunkSize, sortedEntries.count)
            let batch = sortedEntries[batchStart..<batchEnd]
            let actions = await analyzeIncrementalBatch(
                batch,
                hashSnapshot: hashSnapshot,
                indexedAtSnapshot: indexedAtSnapshot
            )

            for action in actions.sorted(by: { $0.relativePath < $1.relativePath }) {
                switch action {
                case .unchanged:
                    break
                case .reindexed(let relativePath, let indexed):
                    removeIndexedFile(relativePath)
                    addIndexedFile(indexed)
                    changedFiles.append(indexed)
                    updatedCount += 1
                case .failed(let relativePath):
                    removeIndexedFile(relativePath)
                    failedReindexPaths.insert(relativePath)
                }
                processed += 1
                _indexingProgress = (current: processed, total: totalToProcess)
            }
        }

        return IncrementalPipelineResult(
            updatedCount: updatedCount,
            failedReindexPaths: failedReindexPaths,
            changedFiles: changedFiles,
            wasCancelled: false
        )
    }

    private func analyzeIncrementalBatch(
        _ entries: ArraySlice<(key: String, value: FileNode)>,
        hashSnapshot: [String: UInt64],
        indexedAtSnapshot: [String: Date]
    ) async -> [IncrementalReindexAction] {
        await withTaskGroup(
            of: IncrementalReindexAction.self,
            returning: [IncrementalReindexAction].self
        ) { group in
            for entry in entries {
                let relativePath = entry.key
                let node = entry.value
                let existingHash = hashSnapshot[node.absolutePath]
                let existingIndexedAt = indexedAtSnapshot[relativePath]

                group.addTask {
                    if let (indexed, content) = SymbolExtractor.indexFileWithContent(
                        absolutePath: node.absolutePath,
                        relativePath: relativePath,
                        language: node.language
                    ) {
                        let hash = SymbolExtractor.fnv1aHash(Data(content.utf8))
                        if let existingHash, existingHash == hash {
                            return .unchanged(relativePath: relativePath)
                        }
                        return .reindexed(relativePath: relativePath, indexed: indexed)
                    }

                    if let existingIndexedAt, existingIndexedAt >= node.modifiedAt {
                        return .unchanged(relativePath: relativePath)
                    }
                    return .failed(relativePath: relativePath)
                }
            }

            var actions: [IncrementalReindexAction] = []
            for await action in group {
                actions.append(action)
            }
            return actions
        }
    }
}
