import Foundation

// MARK: - SemanticIndex Persistence

extension SemanticIndex {
    private struct PersistenceMetadata: Codable {
        let simHash: UInt64
        let totalChunks: Int
        let totalFiles: Int
    }

    /// Save index state as JSONL plus metadata.
    func persist() async {
        guard let path = persistencePath else { return }
        let encoder = JSONEncoder()

        var lines: [String] = []
        for chunk in chunks.values {
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
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        var loadedChunks: [SemanticChunk] = []
        for line in lines {
            if let data = line.data(using: .utf8),
               let chunk = try? decoder.decode(SemanticChunk.self, from: data) {
                loadedChunks.append(chunk)
            }
        }

        clear()
        for chunk in loadedChunks {
            addChunks([chunk], forFile: chunk.filePath)
        }
        recalcAvgDocLength()

        let metaPath = path.deletingLastPathComponent().appendingPathComponent("semantic.meta.json")
        if let metaData = try? Data(contentsOf: metaPath),
           let meta = try? decoder.decode(PersistenceMetadata.self, from: metaData) {
            currentSimHash = meta.simHash
            Self.logger.info("loadFromDisk: restored \(loadedChunks.count) chunks, simHash=\(meta.simHash)")
        }
    }
}
