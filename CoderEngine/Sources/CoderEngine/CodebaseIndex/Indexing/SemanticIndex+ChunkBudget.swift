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

        // Ordina per ultimo accesso (i meno recenti prima)
        let sortedByAccess = chunkAccessOrder
            .sorted { $0.value < $1.value }

        var evicted = 0
        for (chunkId, _) in sortedByAccess {
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
        docLengths.removeValue(forKey: chunkId)
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
