import Foundation
import os

extension CodebaseIndex {
    private static let unifiedIndexingScale = 10_000

    /// Avanzamento 0…1 su **tutta** la pipeline: file → semantic (BM25) → embedding.
    fileprivate func setUnifiedIndexingProgress(_ unitFraction: Double) {
        let clamped = min(1.0, max(0.0, unitFraction))
        let c = min(Self.unifiedIndexingScale, Int(clamped * Double(Self.unifiedIndexingScale)))
        _indexingProgress = (current: c, total: Self.unifiedIndexingScale)
    }

    // MARK: - Public API: Indexing

    /// Index the complete workspace (full scan)
    public func indexWorkspace(
        paths: [URL],
        excludedPaths: [String] = [],
        excludedFilePatterns: [String] = [],
        respectGitignore: Bool = true
    ) async -> IndexResult {
        var transaction = beginIndexingTransaction(operationName: "indexWorkspace")
        // Consente a `status` / UI di vedere `.indexing` prima del blocco sincrono (albero file, ecc.).
        await Task.yield()
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

        let vectorEnabled = IndexFeatureFlags.vectorSearchEnabled
        let wFile: Double = vectorEnabled ? 0.50 : 0.62
        let wSemantic: Double = vectorEnabled ? 0.35 : 0.38
        let wEmbed: Double = vectorEnabled ? 0.15 : 0.0

        let cacheDir = Self.cacheDirectory(for: paths)
        let primaryCacheURL = cacheDir.appendingPathComponent(Self.primarySymbolCacheFileName)
        let settingsKey = Self.primaryCacheSettingsKey(
            excludedPaths: excludedPaths,
            excludedFilePatterns: excludedFilePatterns,
            respectGitignore: respectGitignore
        )
        let pathsKey = Self.indexCachePathsKey(for: paths)

        setUnifiedIndexingProgress(0)

        var reindexedForSemantic: [IndexedFile] = []
        var semanticPathsRemoved: [String] = []

        if let hydration = await loadPrimarySymbolCacheHydration(
            cacheURL: primaryCacheURL,
            filesToIndex: filesToIndex,
            workspacePathsKey: pathsKey,
            settingsKey: settingsKey
        ) {
            semanticPathsRemoved = hydration.semanticRemovals
            let fileTotal = max(1, filesToIndex.count)
            var processed = 0

            if Task.isCancelled {
                return makeCurrentIndexResult(durationMs: Int(Date().timeIntervalSince(startTime) * 1000))
            }
            for f in hydration.reusableFiles {
                addIndexedFile(f)
                processed += 1
            }
            setUnifiedIndexingProgress(wFile * Double(processed) / Double(fileTotal))

            if !hydration.filesToReindex.isEmpty {
                let batchSize = Self.indexParallelSymbolBatchSize
                for batchStart in stride(from: 0, to: hydration.filesToReindex.count, by: batchSize) {
                    if Task.isCancelled {
                        return makeCurrentIndexResult(durationMs: Int(Date().timeIntervalSince(startTime) * 1000))
                    }
                    let batchEnd = min(batchStart + batchSize, hydration.filesToReindex.count)
                    let batch = hydration.filesToReindex[batchStart..<batchEnd]
                    let results: [IndexedFile] = await indexFilesInParallel(batch: batch)
                    for indexed in results {
                        addIndexedFile(indexed)
                        reindexedForSemantic.append(indexed)
                        processed += 1
                    }
                    setUnifiedIndexingProgress(wFile * Double(processed) / Double(fileTotal))
                }
                Self.logger.info(
                    "indexWorkspace: primary symbol cache partial — reused \(hydration.reusableFiles.count, privacy: .public), reindexed \(hydration.filesToReindex.count, privacy: .public)"
                )
            } else if !hydration.reusableFiles.isEmpty {
                Self.logger.info(
                    "indexWorkspace: restored primary symbol cache fully (\(hydration.reusableFiles.count, privacy: .public) files)"
                )
            }
            totalFilesScanned = indexedFiles.count
        } else {
            let batchSize = Self.indexParallelSymbolBatchSize
            for batchStart in stride(from: 0, to: filesToIndex.count, by: batchSize) {
                if Task.isCancelled {
                    return makeCurrentIndexResult(durationMs: Int(Date().timeIntervalSince(startTime) * 1000))
                }
                let batchEnd = min(batchStart + batchSize, filesToIndex.count)
                let batch = filesToIndex[batchStart..<batchEnd]

                let results: [IndexedFile] = await indexFilesInParallel(batch: batch)

                for indexed in results {
                    addIndexedFile(indexed)
                    totalFilesScanned += 1
                }
                setUnifiedIndexingProgress(wFile * Double(batchEnd) / Double(max(1, filesToIndex.count)))
            }
        }

        // 3. Build import graph
        buildImportGraph()

        // 4. Build semantic index (BM25 + AST chunking)
        let semanticCachePath = cacheDir.appendingPathComponent("semantic.jsonl")
        await semanticIndex.setPersistencePath(semanticCachePath)
        setUnifiedIndexingProgress(wFile + wSemantic * 0.02)

        let allIndexed = indexedFiles.values.sorted { $0.relativePath < $1.relativePath }
        if let firstRoot = paths.first {
            var semanticStatus = await semanticIndex.status()
            if semanticStatus.totalChunks == 0 {
                await semanticIndex.loadFromDisk()
            }
            semanticStatus = await semanticIndex.status()

            let hadDiskSemantic = semanticStatus.totalChunks > 0
            let newMerkle = MerkleTree.build(root: firstRoot)
            let newSimHash = newMerkle.map { MerkleTree.simHash(of: $0) } ?? 0

            let didSemanticRemovals = !semanticPathsRemoved.isEmpty
            let didSymbolReindex = !reindexedForSemantic.isEmpty

            if !hadDiskSemantic {
                Self.logger.info("indexWorkspace: no persisted semantic index — full build")
                await semanticIndex.buildIndex(
                    indexedFiles: allIndexed,
                    workspaceRoot: firstRoot,
                    onIndexedFileBatchComplete: { done, tot in
                        let frac = wFile + wSemantic * Double(done) / Double(max(1, tot))
                        await self.setUnifiedIndexingProgress(frac)
                    }
                )
            } else if didSemanticRemovals || didSymbolReindex {
                if didSemanticRemovals {
                    for rel in semanticPathsRemoved {
                        await semanticIndex.removeFile(rel)
                    }
                }
                if didSymbolReindex {
                    Self.logger.info(
                        "indexWorkspace: semantic incremental update (\(reindexedForSemantic.count, privacy: .public) files)"
                    )
                    await semanticIndex.incrementalUpdate(
                        changedFiles: reindexedForSemantic,
                        workspaceRoot: firstRoot
                    )
                }
                if didSemanticRemovals, !didSymbolReindex {
                    await semanticIndex.alignMerkleState(withWorkspaceRoot: firstRoot)
                }
                setUnifiedIndexingProgress(wFile + wSemantic)
            } else if semanticStatus.simHash == newSimHash && newSimHash != 0 {
                Self.logger.info(
                    "indexWorkspace: reusing persisted semantic index (\(semanticStatus.totalChunks, privacy: .public) chunks, simHash match)"
                )
                setUnifiedIndexingProgress(wFile + wSemantic)
            } else {
                Self.logger.info("indexWorkspace: persisted semantic index stale, rebuilding")
                await semanticIndex.buildIndex(
                    indexedFiles: allIndexed,
                    workspaceRoot: firstRoot,
                    onIndexedFileBatchComplete: { done, tot in
                        let frac = wFile + wSemantic * Double(done) / Double(max(1, tot))
                        await self.setUnifiedIndexingProgress(frac)
                    }
                )
            }
        }

        // 5. Vector embedding pipeline (if enabled)
        if vectorEnabled {
            let semanticChunks = await semanticIndex.allChunks()
            if !semanticChunks.isEmpty {
                await generateEmbeddingsForChunks(semanticChunks)
                while await isEmbeddingActive {
                    let embProgress = await embeddingProgress
                    setUnifiedIndexingProgress(wFile + wSemantic + wEmbed * embProgress)
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }

        setUnifiedIndexingProgress(1.0)

        if !Task.isCancelled {
            savePrimarySymbolCache(
                cacheURL: primaryCacheURL,
                paths: paths,
                excludedPaths: excludedPaths,
                excludedFilePatterns: excludedFilePatterns,
                respectGitignore: respectGitignore
            )
        }

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

    private func indexFilesInParallel(batch: ArraySlice<FileNode>) async -> [IndexedFile] {
        await withTaskGroup(of: IndexedFile?.self, returning: [IndexedFile].self) { group in
            for node in batch {
                group.addTask {
                    SymbolExtractor.indexFile(
                        absolutePath: node.absolutePath,
                        relativePath: node.relativePath,
                        language: node.language
                    )
                }
            }
            var collected: [IndexedFile] = []
            for await result in group {
                if let indexed = result {
                    collected.append(indexed)
                }
            }
            return collected
        }
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
