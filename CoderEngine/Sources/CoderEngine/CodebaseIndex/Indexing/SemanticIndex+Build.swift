import Foundation

// MARK: - SemanticIndex Build and Update

extension SemanticIndex {
    // MARK: - Full Index Build

    /// Build the semantic index from a set of `IndexedFile`.
    /// Main entry point after `CodebaseIndex` completes a workspace scan.
    public func buildIndex(
        indexedFiles: [IndexedFile],
        workspaceRoot: URL,
        contentCache: [String: String] = [:]
    ) async {
        Self.logger.info("buildIndex: starting for \(indexedFiles.count) files")

        chunks.removeAll()
        invertedIndex.removeAll()
        termFrequencies.removeAll()
        docLengths.removeAll()
        fileToChunks.removeAll()

        merkleRoot = MerkleTree.build(root: workspaceRoot)
        if let root = merkleRoot {
            currentSimHash = MerkleTree.simHash(of: root)
        }

        let chunkBatchSize = 64
        for batchStart in stride(from: 0, to: indexedFiles.count, by: chunkBatchSize) {
            let batchEnd = min(batchStart + chunkBatchSize, indexedFiles.count)
            let batch = indexedFiles[batchStart..<batchEnd]

            let batchResults: [(String, [SemanticChunk])] = await withTaskGroup(
                of: (String, [SemanticChunk])?.self,
                returning: [(String, [SemanticChunk])].self
            ) { group in
                for indexed in batch {
                    let cachedContent = contentCache[indexed.absolutePath]
                    group.addTask {
                        let content: String
                        if let cached = cachedContent {
                            content = cached
                        } else {
                            guard let read = try? String(contentsOfFile: indexed.absolutePath, encoding: .utf8) else {
                                return nil
                            }
                            content = read
                        }
                        let fileChunks = SemanticChunker.chunk(indexedFile: indexed, fileContent: content)
                        return (indexed.relativePath, fileChunks)
                    }
                }

                var collected: [(String, [SemanticChunk])] = []
                for await result in group {
                    if let pair = result {
                        collected.append(pair)
                    }
                }
                return collected
            }

            for (relativePath, fileChunks) in batchResults {
                addChunks(fileChunks, forFile: relativePath)
            }
        }

        recalcAvgDocLength()
        Self.logger.info(
            "buildIndex: completed — \(self.chunks.count) chunks, \(self.invertedIndex.count) tokens, \(self.fileToChunks.count) files"
        )

        if persistencePath != nil {
            await persist()
        }
    }

    /// Incrementally update the index for changed files.
    public func incrementalUpdate(
        changedFiles: [IndexedFile],
        workspaceRoot: URL
    ) async {
        let newMerkle = MerkleTree.build(root: workspaceRoot)

        if let oldRoot = merkleRoot, let newRoot = newMerkle {
            let changes = MerkleTree.diff(old: oldRoot, new: newRoot)
            merkleRoot = newRoot
            currentSimHash = MerkleTree.simHash(of: newRoot)

            for removedPath in changes.removed {
                removeChunksForFile(removedPath)
            }
        } else {
            merkleRoot = newMerkle
            if let root = newMerkle {
                currentSimHash = MerkleTree.simHash(of: root)
            }
        }

        for indexed in changedFiles {
            removeChunksForFile(indexed.relativePath)

            let content: String
            do {
                content = try String(contentsOfFile: indexed.absolutePath, encoding: .utf8)
            } catch {
                continue
            }

            let fileChunks = SemanticChunker.chunk(indexedFile: indexed, fileContent: content)
            addChunks(fileChunks, forFile: indexed.relativePath)
        }

        recalcAvgDocLength()

        // Persist after incremental update so the on-disk index stays fresh
        if persistencePath != nil {
            await persist()
        }
    }

    /// Update a single file (called from file watcher callbacks).
    /// Uses async file I/O to avoid blocking the actor's serial executor.
    public func updateFile(_ indexed: IndexedFile) async {
        removeChunksForFile(indexed.relativePath)

        // Read file content off the actor's executor to prevent blocking
        let content: String? = await Task.detached(priority: .utility) {
            try? String(contentsOfFile: indexed.absolutePath, encoding: .utf8)
        }.value

        guard let content else { return }

        let fileChunks = SemanticChunker.chunk(indexedFile: indexed, fileContent: content)
        addChunks(fileChunks, forFile: indexed.relativePath)
        recalcAvgDocLength()

        // Persist incrementally so the on-disk index stays fresh
        if persistencePath != nil {
            await persist()
        }
    }

    /// Remove all semantic chunks for a single file.
    public func removeFile(_ relativePath: String) {
        removeChunksForFile(relativePath)
        recalcAvgDocLength()
    }

    /// Clear the entire semantic index state.
    public func clear() {
        chunks.removeAll()
        invertedIndex.removeAll()
        termFrequencies.removeAll()
        docLengths.removeAll()
        avgDocLength = 0
        merkleRoot = nil
        currentSimHash = 0
        fileToChunks.removeAll()
    }
}
