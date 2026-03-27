import Foundation

extension SemanticIndex {
    func writeFullPersistenceSnapshot(
        orderedChunks: [SemanticChunk],
        encoder: JSONEncoder,
        to path: URL
    ) async throws {
        try await Self.writeJSONLAtomically(to: path) { handle in
            for chunk in orderedChunks {
                try Self.writeJSONLLine(for: chunk, encoder: encoder, to: handle)
            }
        }
    }

    func writeIncrementalPersistenceSnapshot(
        dirtyChunkIds: Set<String>,
        encoder: JSONEncoder,
        to path: URL
    ) async throws {
        try await Self.writeJSONLAtomically(to: path) { handle in
            for filePath in dirtyFilePaths.sorted() {
                try Self.writeUTF8Line("#REMOVE:\(filePath)", to: handle)
            }

            for chunkId in dirtyChunkIds.sorted() {
                guard let chunk = chunks[chunkId] else { continue }
                try Self.writeJSONLLine(for: chunk, encoder: encoder, to: handle)
            }
        }
    }

    func loadPersistedChunks(from path: URL, decoder: JSONDecoder) async throws -> [SemanticChunk] {
        let handle = try FileHandle(forReadingFrom: path)
        defer { try? handle.close() }

        var chunks: [SemanticChunk] = []
        for try await line in handle.bytes.lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let chunk = try? decoder.decode(SemanticChunk.self, from: data) else {
                continue
            }
            chunks.append(chunk)
        }
        return chunks
    }

    func applyDelta(from path: URL, decoder: JSONDecoder) async throws {
        let handle = try FileHandle(forReadingFrom: path)
        defer { try? handle.close() }

        var chunksByFile: [String: [SemanticChunk]] = [:]
        for try await line in handle.bytes.lines {
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#REMOVE:") {
                let filePath = String(line.dropFirst("#REMOVE:".count))
                removeChunksForFile(filePath)
                continue
            }
            guard let data = line.data(using: .utf8),
                  let chunk = try? decoder.decode(SemanticChunk.self, from: data) else {
                continue
            }
            chunksByFile[chunk.filePath, default: []].append(chunk)
        }

        for (filePath, fileChunks) in chunksByFile {
            let ordered = fileChunks.sorted { lhs, rhs in
                if lhs.startLine != rhs.startLine { return lhs.startLine < rhs.startLine }
                return lhs.id < rhs.id
            }
            addChunks(ordered, forFile: filePath)
        }
    }

    private static func writeJSONLAtomically(
        to path: URL,
        body: (FileHandle) throws -> Void
    ) async throws {
        let fileManager = FileManager.default
        let tempPath = path.deletingLastPathComponent()
            .appendingPathComponent(".\(path.lastPathComponent).\(UUID().uuidString).tmp")

        if fileManager.fileExists(atPath: tempPath.path) {
            try? fileManager.removeItem(at: tempPath)
        }
        fileManager.createFile(atPath: tempPath.path, contents: nil)

        do {
            let handle = try FileHandle(forWritingTo: tempPath)
            defer { try? handle.close() }
            try body(handle)
            try handle.synchronize()

            if fileManager.fileExists(atPath: path.path) {
                _ = try fileManager.replaceItemAt(path, withItemAt: tempPath)
            } else {
                try fileManager.moveItem(at: tempPath, to: path)
            }
        } catch {
            try? fileManager.removeItem(at: tempPath)
            throw error
        }
    }

    private static func writeJSONLLine<T: Encodable>(
        for value: T,
        encoder: JSONEncoder,
        to handle: FileHandle
    ) throws {
        let data = try encoder.encode(value)
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data("\n".utf8))
    }

    private static func writeUTF8Line(_ line: String, to handle: FileHandle) throws {
        try handle.write(contentsOf: Data(line.utf8))
        try handle.write(contentsOf: Data("\n".utf8))
    }
}
