import Foundation
import os

extension CodebaseIndex {
    // MARK: - Public API: Indexing

    /// Index the complete workspace (full scan)
    public func indexWorkspace(
        paths: [URL],
        excludedPaths: [String] = [],
        excludedFilePatterns: [String] = [],
        respectGitignore: Bool = true
    ) async -> IndexResult {
        var transaction = beginIndexingTransaction(operationName: "indexWorkspace")
        let startTime = transaction.startedAt
        Self.logger.info("indexWorkspace: starting full index for \(paths.map(\.path).joined(separator: ", "), privacy: .public)")
        defer { finishIndexingTransaction(transaction) }

        self.currentWorkspacePaths = paths
        self.excludedPaths = excludedPaths
        self.excludedFilePatterns = excludedFilePatterns
        self.respectGitignore = respectGitignore

        refreshGitignoreRules()

        // Reset state
        resetPrimaryIndexState()

        totalFilesScanned = 0
        totalSymbolsExtracted = 0

        // 1. Build file tree for each root
        rebuildWorkspaceFileTrees()

        // 2. Index source files (extract symbols)
        let sourceFiles = allFileNodes.values.filter {
            $0.isSourceFile && $0.size <= Self.maxFileSize
            && !isFileExcluded($0.relativePath)
            && !isGitignored($0.relativePath, isDirectory: false)
        }
        let filesToIndex = Array(sourceFiles.prefix(Self.maxFiles))
        let indexingProgressTotal = max(1, filesToIndex.count + 1) // + semantic phase
        _indexingProgress = (current: 0, total: indexingProgressTotal)

        // Parallelize symbol extraction: SymbolExtractor.indexFileWithContent is a
        // pure static function (file read + regex), safe to run concurrently.
        // We capture file content here to avoid double I/O in the semantic index phase.
        var contentCache: [String: String] = [:]
        let batchSize = 64
        for batchStart in stride(from: 0, to: filesToIndex.count, by: batchSize) {
            if Task.isCancelled {
                return makeCurrentIndexResult(durationMs: Int(Date().timeIntervalSince(startTime) * 1000))
            }
            let batchEnd = min(batchStart + batchSize, filesToIndex.count)
            let batch = filesToIndex[batchStart..<batchEnd]

            let results: [(IndexedFile, String)] = await withTaskGroup(
                of: (IndexedFile, String)?.self,
                returning: [(IndexedFile, String)].self
            ) { group in
                for node in batch {
                    group.addTask {
                        SymbolExtractor.indexFileWithContent(
                            absolutePath: node.absolutePath,
                            relativePath: node.relativePath,
                            language: node.language
                        )
                    }
                }
                var collected: [(IndexedFile, String)] = []
                for await result in group {
                    if let pair = result {
                        collected.append(pair)
                    }
                }
                return collected
            }

            // Merge results sequentially (actor-isolated mutations)
            for (indexed, content) in results {
                addIndexedFile(indexed)
                contentCache[indexed.absolutePath] = content
                totalFilesScanned += 1
            }
            _indexingProgress = (current: batchEnd, total: indexingProgressTotal)
        }

        // 3. Build import graph
        buildImportGraph()

        // 4. Build semantic index (BM25 + AST chunking)
        // Configure persistence and try loading cached data
        let cacheDir = Self.cacheDirectory(for: paths)
        let semanticCachePath = cacheDir.appendingPathComponent("semantic.jsonl")
        await semanticIndex.setPersistencePath(semanticCachePath)
        _indexingProgress = (current: max(0, indexingProgressTotal - 1), total: indexingProgressTotal)

        let allIndexed = Array(indexedFiles.values)
        if let firstRoot = paths.first {
            // Try loading persisted semantic index
            let semanticStatus = await semanticIndex.status()
            if semanticStatus.totalChunks == 0 {
                await semanticIndex.loadFromDisk()
            }

            // Validate persisted data with Merkle tree simHash
            let loadedStatus = await semanticIndex.status()
            if loadedStatus.totalChunks > 0 {
                let newMerkle = MerkleTree.build(root: firstRoot)
                let newSimHash = newMerkle.map { MerkleTree.simHash(of: $0) } ?? 0
                if loadedStatus.simHash == newSimHash && newSimHash != 0 {
                    Self.logger.info("indexWorkspace: reusing persisted semantic index (\(loadedStatus.totalChunks) chunks, simHash match)")
                } else {
                    Self.logger.info("indexWorkspace: persisted semantic index stale, rebuilding")
                    await semanticIndex.buildIndex(indexedFiles: allIndexed, workspaceRoot: firstRoot, contentCache: contentCache)
                }
            } else {
                await semanticIndex.buildIndex(indexedFiles: allIndexed, workspaceRoot: firstRoot, contentCache: contentCache)
            }
        }
        _indexingProgress = (current: indexingProgressTotal, total: indexingProgressTotal)

        isWorkspaceRebuildInProgress = false
        await flushQueuedRealtimeChanges()
        _indexingProgress = nil
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        indexDurationMs = durationMs
        lastFullIndexAt = Date()
        _status = .ready
        transaction.markCompleted()

        Self.logger.info("indexWorkspace: completed — \(self.totalSymbolsExtracted) symbols, \(self.totalFilesScanned) files, \(durationMs)ms")
        let totalFilesCount = allFileNodes.values.reduce(into: 0) { count, node in
            if node.kind == .file { count += 1 }
        }

        return IndexResult(
            totalFiles: totalFilesCount,
            totalSourceFiles: filesToIndex.count,
            totalSymbols: totalSymbolsExtracted,
            totalDirectories: fileTrees.values.reduce(0) { acc, tree in
                acc + countDirectories(tree)
            },
            durationMs: durationMs,
            languages: languageBreakdown()
        )
    }

    func makeCurrentIndexResult(durationMs: Int, updatedFiles: Int = 0) -> IndexResult {
        let totalFilesCount = allFileNodes.values.reduce(into: 0) { count, node in
            if node.kind == .file { count += 1 }
        }
        return IndexResult(
            totalFiles: totalFilesCount,
            totalSourceFiles: indexedFiles.count,
            totalSymbols: totalSymbolsExtracted,
            totalDirectories: fileTrees.values.reduce(0) { acc, tree in
                acc + countDirectories(tree)
            },
            durationMs: durationMs,
            languages: languageBreakdown(),
            updatedFiles: updatedFiles
        )
    }

    /// Index a single file (for real-time updates)
}
