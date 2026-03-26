import Foundation

// MARK: - Chunk Budget & LRU Eviction

extension SemanticIndex {
    /// Registra un accesso al chunk (aggiorna timestamp LRU).
    func touchChunkAccess(_ chunkId: String) {
        chunkAccessOrder[chunkId] = Date()
    }

    /// Verifica se il budget chunk è superato e, se sì, effettua LRU eviction.
    /// Chiamare dopo ogni addChunks() per mantenere il budget.
    func evictIfNeeded() {
        checkCapacityWarning()

        guard chunks.count > maxChunks else { return }

        let overCount = chunks.count - maxChunks
        Self.logger.warning(
            "evictIfNeeded: budget superato (\(self.chunks.count)/\(self.maxChunks)), evicting \(overCount) chunk LRU"
        )

        // Find the N oldest chunks via linear scan O(n) instead of full sort O(n log n).
        // For typical evictions (overCount << n), this is significantly faster.
        let candidates = findOldestChunks(count: overCount)

        var evicted = 0
        for chunkId in candidates {
            guard evicted < overCount else { break }
            guard chunks[chunkId] != nil else {
                chunkAccessOrder.removeValue(forKey: chunkId)
                continue
            }

            removeChunk(chunkId)
            evicted += 1
        }

        // Fallback: se non ci sono abbastanza entry in accessOrder,
        // rimuovi chunk senza access timestamp (più vecchi implicitamente)
        if evicted < overCount {
            let noAccessChunks = chunks.keys.filter { chunkAccessOrder[$0] == nil }
            for chunkId in noAccessChunks.prefix(overCount - evicted) {
                removeChunk(chunkId)
                evicted += 1
            }
        }

        if evicted > 0 {
            recalcAvgDocLength()
        }
        Self.logger.info("evictIfNeeded: evicted \(evicted) chunks, now \(self.chunks.count)/\(self.maxChunks)")
    }

    /// Find the `count` oldest chunk IDs by access time using a bounded
    /// min-heap approach (single linear pass). O(n) average vs O(n log n)
    /// for a full sort — significant win when evicting a small number of
    /// chunks from a large index (e.g. 10 out of 50K).
    private func findOldestChunks(count: Int) -> [String] {
        guard count > 0 else { return [] }

        // Collect (chunkId, date) tuples, keeping the `count` oldest.
        // We maintain a small array sorted descending (newest first) and
        // only insert when the candidate is older than the newest in our window.
        var oldest: [(id: String, date: Date)] = []
        oldest.reserveCapacity(min(count + 1, chunkAccessOrder.count))

        for (chunkId, date) in chunkAccessOrder {
            if oldest.count < count {
                oldest.append((chunkId, date))
                if oldest.count == count {
                    oldest.sort { $0.date > $1.date } // newest first
                }
            } else if date < oldest[0].date {
                oldest[0] = (chunkId, date)
                // Bubble down to maintain newest-first order
                oldest.sort { $0.date > $1.date }
            }
        }

        return oldest.map(\.id)
    }

    /// Log di warning quando si supera l'80% della capacità.
    func checkCapacityWarning() {
        let ratio = Double(chunks.count) / Double(maxChunks)
        if ratio >= Self.capacityWarningThreshold && ratio < 1.0 {
            Self.logger.warning(
                "chunk budget: \(Int(ratio * 100))% capacità (\(self.chunks.count)/\(self.maxChunks))"
            )
        }
    }

    /// Rimuove un singolo chunk dall'indice e dalle strutture correlate.
    private func removeChunk(_ chunkId: String) {
        guard let chunk = chunks.removeValue(forKey: chunkId) else { return }

        // Rimuovi da invertedIndex
        if let tfs = termFrequencies[chunkId] {
            for token in tfs.keys {
                invertedIndex[token]?.remove(chunkId)
                if invertedIndex[token]?.isEmpty == true {
                    invertedIndex.removeValue(forKey: token)
                }
            }
        }

        termFrequencies.removeValue(forKey: chunkId)
        if let len = docLengths.removeValue(forKey: chunkId) {
            totalTokenCount -= len
        }
        chunkAccessOrder.removeValue(forKey: chunkId)

        // Rimuovi da fileToChunks
        if var fileChunks = fileToChunks[chunk.filePath] {
            fileChunks.removeAll { $0 == chunkId }
            if fileChunks.isEmpty {
                fileToChunks.removeValue(forKey: chunk.filePath)
            } else {
                fileToChunks[chunk.filePath] = fileChunks
            }
        }
    }

    /// Pulisce anche gli accessOrder durante clear().
    func clearAccessOrder() {
        chunkAccessOrder.removeAll()
    }
}
