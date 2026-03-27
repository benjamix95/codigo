import Foundation

// MARK: - SemanticIndex Persistence

extension SemanticIndex {
    private static let currentPersistenceVersion: Int = 3
    private static let currentPersistenceSchema: String = "semantic_index_jsonl_v3"

    private struct PersistenceMetadata: Codable {
        let version: Int
        let schema: String
        let simHash: UInt64
        let totalChunks: Int
        let totalFiles: Int
        let tokenizerFingerprint: String
        let stopWordsFingerprint: String
        let synonymsFingerprint: String
    }

    /// Schedule a debounced persist. Cancels any pending persist task and
    /// starts a new one that fires after `persistDebounceNs`. Multiple rapid
    /// updates (e.g. file watcher batch) coalesce into a single disk write.
    func scheduleDebouncedPersist() {
        persistDebounceTask?.cancel()
        persistDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.persistDebounceNs)
            } catch {
                return // Cancelled — a newer persist was scheduled.
            }
            guard !Task.isCancelled else { return }
            await self?.persist()
        }
    }

    /// Save index state as JSONL plus metadata.
    /// Skips the expensive full rewrite when no files have been modified
    /// since the last persist and the index file already exists on disk.
    func persist() async {
        guard let path = persistencePath else { return }

        // Early return: no dirty files and index already on disk → only update metadata.
        if dirtyFilePaths.isEmpty && FileManager.default.fileExists(atPath: path.path) {
            Self.logger.debug("persist: no dirty files, skipping full rewrite")
            persistMetadata(at: path)
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // Collect only chunks belonging to dirty files for targeted write.
        // When all files are dirty (e.g. full build), this is equivalent to
        // a full rewrite. When only a few files changed, we avoid encoding
        // and writing the untouched ~95% of chunks.
        let dirtyChunkIds: Set<String> = {
            var ids = Set<String>()
            for filePath in dirtyFilePaths {
                if let fileChunkIds = fileToChunks[filePath] {
                    ids.formUnion(fileChunkIds)
                }
            }
            return ids
        }()

        // If dirty chunks are <50% of total AND the index is large enough
        // (>=1000 chunks) AND an index file already exists, write an
        // incremental delta file. Otherwise do a full rewrite.
        // The 1000-chunk minimum avoids delta overhead on small indices
        // where full rewrite is already fast.
        let useIncremental = !dirtyChunkIds.isEmpty
            && chunks.count >= 1_000
            && dirtyChunkIds.count < chunks.count / 2
            && FileManager.default.fileExists(atPath: path.path)

        if useIncremental {
            await persistIncremental(
                dirtyChunkIds: dirtyChunkIds,
                encoder: encoder,
                indexPath: path
            )
            return
        }

        // Full rewrite — sort for deterministic output (required by tests).
        // This path only triggers when >50% of files are dirty or no index
        // exists on disk, which is infrequent (initial build, full rebuild).
        let orderedChunks = chunks.values.sorted { lhs, rhs in
            if lhs.filePath != rhs.filePath { return lhs.filePath < rhs.filePath }
            if lhs.startLine != rhs.startLine { return lhs.startLine < rhs.startLine }
            return lhs.id < rhs.id
        }
        do {
            try await writeFullPersistenceSnapshot(
                orderedChunks: orderedChunks,
                encoder: encoder,
                to: path
            )
        } catch {
            Self.logger.error("persist: failed to write semantic index — \(error.localizedDescription)")
            return
        }

        // Clear dirty set after successful write.
        dirtyFilePaths.removeAll()
        persistMetadata(at: path)
    }

    /// Incremental persist: writes only chunks belonging to dirty files into
    /// a `.delta.jsonl` sidecar. On next `loadFromDisk`, deltas are merged
    /// with the base index. The next full persist compacts everything.
    private func persistIncremental(
        dirtyChunkIds: Set<String>,
        encoder: JSONEncoder,
        indexPath: URL
    ) async {
        let deltaPath = Self.deltaPath(for: indexPath)

        do {
            try await writeIncrementalPersistenceSnapshot(
                dirtyChunkIds: dirtyChunkIds,
                encoder: encoder,
                to: deltaPath
            )
        } catch {
            Self.logger.error("persistIncremental: failed to write delta — \(error.localizedDescription)")
            // Fallback: schedule full persist
            dirtyFilePaths.removeAll() // prevent infinite loop
            await persist()
            return
        }

        dirtyFilePaths.removeAll()
        persistMetadata(at: indexPath)
        Self.logger.info("persistIncremental: wrote \(dirtyChunkIds.count) dirty chunks to delta")
    }

    private static func deltaPath(for indexPath: URL) -> URL {
        indexPath.deletingLastPathComponent()
            .appendingPathComponent("semantic.delta.jsonl")
    }

    /// Write metadata file (small, always fast).
    private func persistMetadata(at indexPath: URL) {
        let metaPath = indexPath.deletingLastPathComponent()
            .appendingPathComponent("semantic.meta.json")
        let meta = PersistenceMetadata(
            version: Self.currentPersistenceVersion,
            schema: Self.currentPersistenceSchema,
            simHash: currentSimHash,
            totalChunks: chunks.count,
            totalFiles: fileToChunks.count,
            tokenizerFingerprint: Self.tokenizerFingerprint,
            stopWordsFingerprint: Self.stopWordsFingerprint,
            synonymsFingerprint: Self.synonymsFingerprint
        )
        do {
            let metaData = try JSONEncoder().encode(meta)
            try metaData.write(to: metaPath, options: .atomic)
        } catch {
            Self.logger.error("persist: failed to write semantic metadata — \(error.localizedDescription)")
        }
    }

    /// Load index from disk.
    public func loadFromDisk() async {
        guard let path = persistencePath,
              FileManager.default.fileExists(atPath: path.path) else {
            return
        }

        let decoder = JSONDecoder()

        // Verify schema/version BEFORE loading chunks to avoid stale or incompatible data.
        let metaPath = path.deletingLastPathComponent().appendingPathComponent("semantic.meta.json")
        guard let metaData = try? Data(contentsOf: metaPath),
              let metadata = try? decoder.decode(PersistenceMetadata.self, from: metaData) else {
            Self.logger.notice("loadFromDisk: missing or invalid semantic metadata — forcing rebuild")
            clear()
            return
        }

        guard metadata.version == Self.currentPersistenceVersion else {
            Self.logger.notice("loadFromDisk: version mismatch (found \(metadata.version), expected \(Self.currentPersistenceVersion)) — forcing rebuild")
            clear()
            return
        }

        guard metadata.schema == Self.currentPersistenceSchema else {
            Self.logger.notice("loadFromDisk: schema mismatch (found \(metadata.schema), expected \(Self.currentPersistenceSchema)) — forcing rebuild")
            clear()
            return
        }
        guard metadata.tokenizerFingerprint == Self.tokenizerFingerprint,
              metadata.stopWordsFingerprint == Self.stopWordsFingerprint,
              metadata.synonymsFingerprint == Self.synonymsFingerprint else {
            Self.logger.notice("loadFromDisk: tokenizer fingerprint mismatch — forcing rebuild")
            clear()
            return
        }

        guard let loadedChunks = try? await loadPersistedChunks(from: path, decoder: decoder) else {
            return
        }

        // When a delta file exists, the base file may have fewer chunks than
        // metadata.totalChunks (metadata reflects the post-delta state).
        // Only enforce the count check when no delta is pending.
        let deltaPath = Self.deltaPath(for: path)
        let hasPendingDelta = FileManager.default.fileExists(atPath: deltaPath.path)
        if !hasPendingDelta {
            guard loadedChunks.count == metadata.totalChunks else {
                Self.logger.notice("loadFromDisk: chunk count mismatch (loaded \(loadedChunks.count), metadata \(metadata.totalChunks)) — forcing rebuild")
                clear()
                return
            }
        }

        clear()
        let groupedByFile = Dictionary(grouping: loadedChunks, by: \.filePath)
        for (relativePath, fileChunks) in groupedByFile {
            let ordered = fileChunks.sorted { lhs, rhs in
                if lhs.startLine != rhs.startLine { return lhs.startLine < rhs.startLine }
                return lhs.id < rhs.id
            }
            addChunks(ordered, forFile: relativePath)
        }
        rebuildTotalTokenCount()
        currentSimHash = metadata.simHash

        // Apply incremental delta if present
        if FileManager.default.fileExists(atPath: deltaPath.path) {
            try? await applyDelta(from: deltaPath, decoder: decoder)
            rebuildTotalTokenCount()
            // Remove delta after successful merge — next persist will be a full write
            try? FileManager.default.removeItem(at: deltaPath)
            Self.logger.info("loadFromDisk: applied incremental delta, now \(self.chunks.count) chunks")
        }

        Self.logger.info("loadFromDisk: restored \(self.chunks.count) chunks, simHash=\(metadata.simHash)")
    }

    private static var tokenizerFingerprint: String {
        "porter_v1"
    }

    private static var stopWordsFingerprint: String {
        fingerprintHex(for: stopWords.sorted().joined(separator: "|"))
    }

    private static var synonymsFingerprint: String {
        let flattened = synonymMap
            .map { key, values in
                "\(key):\(values.joined(separator: ","))"
            }
            .sorted()
            .joined(separator: "|")
        return fingerprintHex(for: flattened)
    }

    private static func fingerprintHex(for value: String) -> String {
        let hash = value.utf8.reduce(UInt64(1469598103934665603)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1099511628211
        }
        return String(hash, radix: 16)
    }
}
