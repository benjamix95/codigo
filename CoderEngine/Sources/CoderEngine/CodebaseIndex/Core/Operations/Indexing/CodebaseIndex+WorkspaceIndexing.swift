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
        _status = .indexing
        Self.logger.info("indexWorkspace: starting full index for \(paths.map(\.path).joined(separator: ", "), privacy: .public)")

        self.currentWorkspacePaths = paths
        self.excludedPaths = excludedPaths
        self.excludedFilePatterns = excludedFilePatterns
        self.respectGitignore = respectGitignore

        // Load .gitignore rules if enabled
        if respectGitignore, let firstRoot = paths.first {
            loadGitignoreRules(for: firstRoot)
        } else {
            gitignoreRules = []
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
        let totalToIndex = filesToIndex.count
        _indexingProgress = (current: 0, total: totalToIndex)

        // Parallelize symbol extraction: SymbolExtractor.indexFileWithContent is a
        // pure static function (file read + regex), safe to run concurrently.
        // We capture file content here to avoid double I/O in the semantic index phase.
        var contentCache: [String: String] = [:]
        let batchSize = 64
        for batchStart in stride(from: 0, to: filesToIndex.count, by: batchSize) {
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
            _indexingProgress = (current: batchEnd, total: totalToIndex)
        }

        // 3. Build import graph
        buildImportGraph()

        // 4. Build semantic index (BM25 + AST chunking)
        // Configure persistence and try loading cached data
        let cacheDir = Self.cacheDirectory(for: paths)
        let semanticCachePath = cacheDir.appendingPathComponent("semantic.jsonl")
        await semanticIndex.setPersistencePath(semanticCachePath)

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

        _indexingProgress = nil
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        indexDurationMs = durationMs
        lastFullIndexAt = Date()
        _status = .ready

        Self.logger.info("indexWorkspace: completed — \(self.totalSymbolsExtracted) symbols, \(self.totalFilesScanned) files, \(durationMs)ms")

        return IndexResult(
            totalFiles: allFileNodes.count,
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
        _status = .indexing
        Self.logger.info("incrementalUpdate: starting")

        var updatedCount = 0
        var removedCount = 0
        var changedFiles: [IndexedFile] = []

        // Rebuild file trees from disk to avoid stale file nodes.
        fileTrees.removeAll()
        allFileNodes.removeAll()
        for rootURL in currentWorkspacePaths {
            let tree = buildFileTree(at: rootURL, relativePath: "", depth: 0)
            fileTrees[rootURL.path] = tree
            flattenNodes(tree)
        }

        let sourceNodes = allFileNodes.filter { _, node in
            node.isSourceFile && node.size <= Self.maxFileSize
        }

        let currentSourcePaths = Set(sourceNodes.keys)
        let indexedPaths = Set(indexedFiles.keys)
        let removedPaths = indexedPaths.subtracting(currentSourcePaths)
        for relativePath in removedPaths {
            removeIndexedFile(relativePath)
            removedCount += 1
        }

        for (relativePath, node) in sourceNodes {
            guard node.isSourceFile, node.size <= Self.maxFileSize else { continue }

            // Check if file was modified
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: node.absolutePath),
                let modDate = attrs[.modificationDate] as? Date
            else { continue }

            let existingFile = indexedFiles[relativePath]
            if let existing = existingFile, existing.indexedAt >= modDate {
                continue  // File not modified since last index
            }

            // Check content hash
            if let data = FileManager.default.contents(atPath: node.absolutePath) {
                let hash = SymbolExtractor.fnv1aHash(data)
                if let existingHash = contentHashes[node.absolutePath], existingHash == hash {
                    continue  // Content unchanged
                }
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
            }
        }

        // Re-build import graph
        buildImportGraph()

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
        } else if !changedFiles.isEmpty || removedCount > 0 {
            await semanticIndex.clear()
        }

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        indexDurationMs = durationMs
        _status = .ready

        Self.logger.info("incrementalUpdate: completed — \(updatedCount) updated, \(removedCount) removed, \(durationMs)ms")

        return IndexResult(
            totalFiles: allFileNodes.count,
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

    /// Index a single file (for real-time updates)
}
