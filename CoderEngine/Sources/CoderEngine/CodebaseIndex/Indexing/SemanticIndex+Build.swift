import Foundation

// MARK: - SemanticIndex Build and Update

extension SemanticIndex {
    private static let merkleRebuildThreshold = 32

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
        deferredMerkleTouchedFiles = 0

        merkleRoot = MerkleTree.build(root: workspaceRoot)
        if let root = merkleRoot {
            currentSimHash = MerkleTree.simHash(of: root)
        }

        let chunkBatchSize = 64
        for batchStart in stride(from: 0, to: indexedFiles.count, by: chunkBatchSize) {
            if Task.isCancelled {
                Self.logger.notice("buildIndex: cancelled at batchStart=\(batchStart)")
                break
            }
            let batchEnd = min(batchStart + chunkBatchSize, indexedFiles.count)
            let batch = indexedFiles[batchStart..<batchEnd]

            let batchResults: [(String, [SemanticChunk])] = await withTaskGroup(
                of: (String, [SemanticChunk])?.self,
                returning: [(String, [SemanticChunk])].self
            ) { group in
                for indexed in batch {
                    let cachedContent = contentCache[indexed.absolutePath]
                    group.addTask {
                        if Task.isCancelled { return nil }
                        let content: String
                        if let cached = cachedContent {
                            content = cached
                        } else {
                            guard let read = SemanticIndex.readTextFile(at: indexed.absolutePath) else {
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
        let shouldRebuildMerkle = shouldRebuildMerkleTree(forChangedFiles: changedFiles)
        if shouldRebuildMerkle {
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
            deferredMerkleTouchedFiles = 0
        } else {
            deferredMerkleTouchedFiles += changedFiles.count
            for indexed in changedFiles {
                currentSimHash = mixSimHash(
                    currentSimHash,
                    token: "\(indexed.relativePath)#\(indexed.contentHash)"
                )
            }
        }

        for indexed in changedFiles {
            removeChunksForFile(indexed.relativePath)

            let content: String
            if let read = SemanticIndex.readTextFile(at: indexed.absolutePath) {
                content = read
            } else {
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
            SemanticIndex.readTextFile(at: indexed.absolutePath)
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
        deferredMerkleTouchedFiles = 0
    }

    private func shouldRebuildMerkleTree(forChangedFiles changedFiles: [IndexedFile]) -> Bool {
        if merkleRoot == nil { return true }
        if changedFiles.count >= Self.merkleRebuildThreshold { return true }
        return deferredMerkleTouchedFiles + changedFiles.count >= Self.merkleRebuildThreshold
    }

    nonisolated static func readTextFile(at path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]) else {
            return nil
        }

        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .utf32,
            .isoLatin1,
            .windowsCP1252,
        ]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func mixSimHash(_ seed: UInt64, token: String) -> UInt64 {
        let tokenHash = token.utf8.reduce(UInt64(1469598103934665603)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1099511628211
        }
        return seed &* 1099511628211 ^ tokenHash
    }
}
