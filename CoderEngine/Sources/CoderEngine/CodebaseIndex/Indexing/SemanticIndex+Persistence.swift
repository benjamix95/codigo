import Foundation

// MARK: - SemanticIndex Persistence

extension SemanticIndex {
    private static let currentPersistenceVersion: Int = 2
    private static let currentPersistenceSchema: String = "semantic_index_jsonl_v2"

    private struct PersistenceMetadata: Codable {
        let version: Int
        let schema: String
        let simHash: UInt64
        let totalChunks: Int
        let totalFiles: Int
    }

    /// Save index state as JSONL plus metadata.
    func persist() async {
        guard let path = persistencePath else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var lines: [String] = []
        let orderedChunks = chunks.values.sorted { lhs, rhs in
            if lhs.filePath != rhs.filePath { return lhs.filePath < rhs.filePath }
            if lhs.startLine != rhs.startLine { return lhs.startLine < rhs.startLine }
            return lhs.id < rhs.id
        }
        for chunk in orderedChunks {
            if let data = try? encoder.encode(chunk),
               let line = String(data: data, encoding: .utf8) {
                lines.append(line)
            }
        }

        let content = lines.joined(separator: "\n")
        do {
            try content.write(to: path, atomically: true, encoding: .utf8)
        } catch {
            Self.logger.error("persist: failed to write semantic index — \(error.localizedDescription)")
            return
        }

        let metaPath = path.deletingLastPathComponent()
            .appendingPathComponent("semantic.meta.json")
        let meta = PersistenceMetadata(
            version: Self.currentPersistenceVersion,
            schema: Self.currentPersistenceSchema,
            simHash: currentSimHash,
            totalChunks: chunks.count,
            totalFiles: fileToChunks.count
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
              let content = try? String(contentsOf: path, encoding: .utf8) else {
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

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        var loadedChunks: [SemanticChunk] = []
        for line in lines {
            if let data = line.data(using: .utf8),
               let chunk = try? decoder.decode(SemanticChunk.self, from: data) {
                loadedChunks.append(chunk)
            }
        }

        guard loadedChunks.count == metadata.totalChunks else {
            Self.logger.notice("loadFromDisk: chunk count mismatch (loaded \(loadedChunks.count), metadata \(metadata.totalChunks)) — forcing rebuild")
            clear()
            return
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
        recalcAvgDocLength()
        currentSimHash = metadata.simHash
        Self.logger.info("loadFromDisk: restored \(loadedChunks.count) chunks, simHash=\(metadata.simHash)")
    }
}
