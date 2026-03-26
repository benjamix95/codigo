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

        if let cachedFiles = await loadValidatedPrimarySymbolCache(
            cacheURL: primaryCacheURL,
            filesToIndex: filesToIndex,
            workspacePathsKey: pathsKey,
            settingsKey: settingsKey
        ) {
            Self.logger.info("indexWorkspace: restored primary symbol cache (\(cachedFiles.count) files)")
            for f in cachedFiles {
                addIndexedFile(f)
            }
            totalFilesScanned = cachedFiles.count
            setUnifiedIndexingProgress(wFile)
        } else {
            let batchSize = 64
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

        let allIndexed = Array(indexedFiles.values)
        if let firstRoot = paths.first {
            let semanticStatus = await semanticIndex.status()
            if semanticStatus.totalChunks == 0 {
                await semanticIndex.loadFromDisk()
            }

            let loadedStatus = await semanticIndex.status()
            if loadedStatus.totalChunks > 0 {
                let newMerkle = MerkleTree.build(root: firstRoot)
                let newSimHash = newMerkle.map { MerkleTree.simHash(of: $0) } ?? 0
                if loadedStatus.simHash == newSimHash && newSimHash != 0 {
                    Self.logger.info("indexWorkspace: reusing persisted semantic index (\(loadedStatus.totalChunks) chunks, simHash match)")
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
            } else {
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
