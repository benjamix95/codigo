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
        guard metadata.tokenizerFingerprint == Self.tokenizerFingerprint,
              metadata.stopWordsFingerprint == Self.stopWordsFingerprint,
              metadata.synonymsFingerprint == Self.synonymsFingerprint else {
            Self.logger.notice("loadFromDisk: tokenizer fingerprint mismatch — forcing rebuild")
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
