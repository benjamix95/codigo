import Foundation

// MARK: - SemanticIndex Index Management

extension SemanticIndex {
    /// Add chunks to the inverted index.
    func addChunks(_ newChunks: [SemanticChunk], forFile relativePath: String) {
        var chunkIds: [String] = []
        let now = Date()

        for chunk in newChunks {
            chunks[chunk.id] = chunk
            chunkIds.append(chunk.id)
            chunkAccessOrder[chunk.id] = now

            let tokens = Self.tokenizeStatic(chunk.contextualizedText)
            var termFrequency: [String: Int] = [:]
            for token in tokens {
                termFrequency[token, default: 0] += 1
            }
            termFrequencies[chunk.id] = termFrequency
            docLengths[chunk.id] = tokens.count
            totalTokenCount += tokens.count

            for token in termFrequency.keys {
                invertedIndex[token, default: []].insert(chunk.id)
            }
        }

        fileToChunks[relativePath] = chunkIds
        dirtyFilePaths.insert(relativePath)
    }

    /// Remove all chunks for a file.
    func removeChunksForFile(_ relativePath: String) {
        guard let chunkIds = fileToChunks[relativePath] else { return }

        for chunkId in chunkIds {
            if let termFrequency = termFrequencies[chunkId] {
                for token in termFrequency.keys {
                    invertedIndex[token]?.remove(chunkId)
                    if invertedIndex[token]?.isEmpty == true {
                        invertedIndex.removeValue(forKey: token)
                    }
                }
            }

            chunks.removeValue(forKey: chunkId)
            termFrequencies.removeValue(forKey: chunkId)
            if let len = docLengths.removeValue(forKey: chunkId) {
                totalTokenCount -= len
            }
            chunkAccessOrder.removeValue(forKey: chunkId)
        }

        fileToChunks.removeValue(forKey: relativePath)
        dirtyFilePaths.insert(relativePath)
    }

    /// Recalculate average document length.
    /// When called without arguments, uses the running `totalTokenCount` for O(1).
    /// The full O(n) recomputation is only used in `loadFromDisk()` to rebuild
    /// `totalTokenCount` from the persisted state.
    func recalcAvgDocLength() {
        avgDocLength = docLengths.isEmpty ? 0 : Double(totalTokenCount) / Double(docLengths.count)
    }

    /// Full O(n) recomputation of totalTokenCount from docLengths.
    /// Used only after loading from disk when the running total is unknown.
    func rebuildTotalTokenCount() {
        totalTokenCount = docLengths.values.reduce(0, +)
        recalcAvgDocLength()
    }
}
