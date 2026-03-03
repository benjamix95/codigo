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
        let startTime = Date()
        var completedSuccessfully = false

        _status = .indexing
        isWorkspaceRebuildInProgress = true
        queuedRealtimeChanges.removeAll(keepingCapacity: true)
        Self.logger.info("indexWorkspace: starting full index for \(paths.map(\.path).joined(separator: ", "), privacy: .public)")
        defer {
            if !completedSuccessfully {
                _indexingProgress = nil
                isWorkspaceRebuildInProgress = false
                queuedRealtimeChanges.removeAll(keepingCapacity: true)
                if _status == .indexing {
                    _status = Task.isCancelled ? .idle : .error
                }
            }
        }

        self.currentWorkspacePaths = paths
        self.excludedPaths = excludedPaths
        self.excludedFilePatterns = excludedFilePatterns
        self.respectGitignore = respectGitignore

        // Load .gitignore rules if enabled
        if respectGitignore {
            gitignoreRules.removeAll()
            gitignoreRulesByRoot.removeAll()
            for root in paths {
                loadGitignoreRules(for: root)
            }
        } else {
            gitignoreRules = []
            gitignoreRulesByRoot = [:]
        }

        // Reset state
        fileTrees.removeAll()
        indexedFiles.removeAll()
        symbolsByName.removeAll()
        symbolsByFile.removeAll()
        symbolsByKind.removeAll()
        allFileNodes.removeAll()
        importGraph.removeAll()
        reverseImportGraph.removeAll()
        contentHashes.removeAll()

        totalFilesScanned = 0
        totalSymbolsExtracted = 0

        // 1. Build file tree for each root
        for rootURL in paths {
            let tree = buildFileTree(
                at: rootURL,
                relativePath: "",
                depth: 0
            )
            fileTrees[rootURL.path] = tree

            // Flatten all file nodes
            flattenNodes(tree)
        }

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
        completedSuccessfully = true

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

    /// Incremental indexing: re-indexes only modified files
    public func incrementalUpdate() async -> IndexResult {
        let startTime = Date()
        var completedSuccessfully = false

        _status = .indexing
        isWorkspaceRebuildInProgress = true
        queuedRealtimeChanges.removeAll(keepingCapacity: true)
        Self.logger.info("incrementalUpdate: starting")
        defer {
            if !completedSuccessfully {
                _indexingProgress = nil
                isWorkspaceRebuildInProgress = false
                queuedRealtimeChanges.removeAll(keepingCapacity: true)
                if _status == .indexing {
                    _status = Task.isCancelled ? .idle : .error
                }
            }
        }

        var updatedCount = 0
        var removedCount = 0
        var changedFiles: [IndexedFile] = []
        var failedReindexPaths: Set<String> = []

        if respectGitignore {
            gitignoreRules.removeAll()
            gitignoreRulesByRoot.removeAll()
            for root in currentWorkspacePaths {
                loadGitignoreRules(for: root)
            }
        } else {
            gitignoreRules = []
            gitignoreRulesByRoot = [:]
        }

        // Rebuild file trees from disk to avoid stale file nodes.
        fileTrees.removeAll()
        allFileNodes.removeAll()
        for rootURL in currentWorkspacePaths {
            let tree = buildFileTree(at: rootURL, relativePath: "", depth: 0)
            fileTrees[rootURL.path] = tree
            flattenNodes(tree)
        }

        let sourceNodes = allFileNodes.filter { _, node in
            node.isSourceFile
                && node.size <= Self.maxFileSize
                && !isFileExcluded(node.relativePath)
                && !isGitignored(node.relativePath, isDirectory: false)
        }

        let currentSourcePaths = Set(sourceNodes.keys)
        let indexedPaths = Set(indexedFiles.keys)
        let removedPaths = indexedPaths.subtracting(currentSourcePaths)
        let totalToProcess = max(1, sourceNodes.count + removedPaths.count + 1) // + semantic phase
        var processed = 0
        _indexingProgress = (current: 0, total: totalToProcess)
        for relativePath in removedPaths {
            if Task.isCancelled {
                return makeCurrentIndexResult(durationMs: Int(Date().timeIntervalSince(startTime) * 1000), updatedFiles: updatedCount + removedCount)
            }
            removeIndexedFile(relativePath)
            removedCount += 1
            processed += 1
            _indexingProgress = (current: processed, total: totalToProcess)
        }

        for (relativePath, node) in sourceNodes {
            if Task.isCancelled {
                return makeCurrentIndexResult(durationMs: Int(Date().timeIntervalSince(startTime) * 1000), updatedFiles: updatedCount + removedCount)
            }
            guard node.isSourceFile, node.size <= Self.maxFileSize else { continue }

            let existingFile = indexedFiles[relativePath]
            let attrs = try? FileManager.default.attributesOfItem(atPath: node.absolutePath)
            let modDate = attrs?[.modificationDate] as? Date

            var hashComputed = false
            // Check content hash
            if let data = FileManager.default.contents(atPath: node.absolutePath) {
                hashComputed = true
                let hash = SymbolExtractor.fnv1aHash(data)
                if let existingHash = contentHashes[node.absolutePath], existingHash == hash {
                    processed += 1
                    _indexingProgress = (current: processed, total: totalToProcess)
                    continue  // Content unchanged
                }
            }
            // Fallback check if hash cannot be computed: skip only when timestamp confirms no changes.
            if !hashComputed, let existing = existingFile, let modDate, existing.indexedAt >= modDate {
                processed += 1
                _indexingProgress = (current: processed, total: totalToProcess)
                continue
            }

            // Re-index this file
            removeIndexedFile(relativePath)

            if let indexed = SymbolExtractor.indexFile(
                absolutePath: node.absolutePath,
                relativePath: relativePath,
                language: node.language
            ) {
                addIndexedFile(indexed)
                updatedCount += 1
                changedFiles.append(indexed)
            } else {
                failedReindexPaths.insert(relativePath)
            }
            processed += 1
            _indexingProgress = (current: processed, total: totalToProcess)
        }

        // Re-build import graph
        buildImportGraph()
        _indexingProgress = (current: max(0, totalToProcess - 1), total: totalToProcess)

        // Update semantic index incrementally (not a full rebuild)
        if let firstRoot = currentWorkspacePaths.first {
            if !changedFiles.isEmpty {
                await semanticIndex.incrementalUpdate(
                    changedFiles: changedFiles,
                    workspaceRoot: firstRoot
                )
            }
            for relativePath in removedPaths {
                await semanticIndex.removeFile(relativePath)
            }
            for relativePath in failedReindexPaths {
                await semanticIndex.removeFile(relativePath)
            }
        } else if !changedFiles.isEmpty || removedCount > 0 {
            await semanticIndex.clear()
        }
        _indexingProgress = (current: totalToProcess, total: totalToProcess)

        isWorkspaceRebuildInProgress = false
        await flushQueuedRealtimeChanges()

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        indexDurationMs = durationMs
        _indexingProgress = nil
        _status = .ready
        completedSuccessfully = true

        Self.logger.info("incrementalUpdate: completed — \(updatedCount) updated, \(removedCount) removed, \(durationMs)ms")
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
            updatedFiles: updatedCount + removedCount
        )
    }

    private func makeCurrentIndexResult(durationMs: Int, updatedFiles: Int = 0) -> IndexResult {
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
