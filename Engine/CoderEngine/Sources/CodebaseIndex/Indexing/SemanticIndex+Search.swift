import Foundation

// MARK: - SemanticIndex Search

extension SemanticIndex {
    // MARK: - Search

    /// Search code snippets by natural language and return ranked chunks.
    public func search(
        query: String,
        targetDirectories: [String] = [],
        numResults: Int = 25
    ) -> [SearchResult] {
        let queryInput = SearchQueryInput(
            query: query,
            targetDirectories: targetDirectories,
            numResults: numResults
        )
        let hits = searchBackend.search(
            query: queryInput,
            snapshot: makeSearchSnapshot()
        )
        lastSearchMetrics = hits.metrics

        guard !hits.hits.isEmpty else {
            Self.logger.debug("search: empty query tokens for '\(query, privacy: .public)'")
            return []
        }

        return hits.hits.compactMap { hit in
            guard let chunk = chunks[hit.chunkId] else { return nil }
            touchChunkAccess(hit.chunkId)
            return SearchResult(chunk: chunk, score: hit.score)
        }
    }

    /// Current index statistics.
    public func status() -> IndexStatus {
        IndexStatus(
            totalChunks: chunks.count,
            totalTokens: invertedIndex.count,
            totalFiles: fileToChunks.count,
            avgDocLength: avgDocLength,
            simHash: currentSimHash,
            hasMerkleTree: merkleRoot != nil
        )
    }

    /// All chunks currently in the index (for vector embedding pipeline).
    public func allChunks() -> [SemanticChunk] {
        Array(chunks.values)
    }

    // MARK: - Tokenization

    func tokenize(_ text: String) -> [String] {
        Self.tokenizeStatic(text)
    }

    private func makeSearchSnapshot() -> SemanticIndexSearchSnapshot {
        SemanticIndexSearchSnapshot(
            chunks: chunks,
            invertedIndex: invertedIndex,
            termFrequencies: termFrequencies,
            docLengths: docLengths,
            avgDocLength: avgDocLength,
            totalDocs: totalDocs,
            k1: k1,
            b: b
        )
    }

    nonisolated static func tokenizeStatic(_ text: String) -> [String] {
        var tokens: [String] = []

        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        for word in words {
            let lower = word.lowercased()
            tokens.append(lower)

            // Porter stemming — normalizes inflected forms (authenticating → authent)
            let stemmed = PorterStemmer.stem(lower)
            if stemmed != lower && stemmed.count >= 2 {
                tokens.append(stemmed)
            }

            let camelSplit = splitCamelCase(word)
                .map { $0.lowercased() }
                .filter { $0.count >= 2 }
            if camelSplit.count > 1 {
                tokens.append(contentsOf: camelSplit)
                // Stem each camelCase part too
                for part in camelSplit {
                    let partStemmed = PorterStemmer.stem(part)
                    if partStemmed != part && partStemmed.count >= 2 {
                        tokens.append(partStemmed)
                    }
                }
            }
        }

        let filtered = tokens.filter { !Self.stopWords.contains($0) }
        var expanded: [String] = []
        var seen = Set<String>()
        for token in filtered where seen.insert(token).inserted {
            expanded.append(token)
        }

        for token in filtered where expanded.count < 3000 {
            if let syns = Self.synonymMap[token] {
                for synonym in syns.prefix(2) where expanded.count < 3000 {
                    let normalized = synonym.lowercased()
                    if normalized == token { continue }
                    if Self.stopWords.contains(normalized) { continue }
                    if let reverse = Self.synonymMap[normalized], reverse.contains(token), seen.contains(normalized) {
                        continue
                    }
                    if seen.insert(normalized).inserted {
                        expanded.append(normalized)
                    }
                }
            }
        }

        // Evita di reintrodurre rumore via sinonimi.
        return expanded.filter { !Self.stopWords.contains($0) }
    }

    private static func splitCamelCase(_ word: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for char in word {
            if char.isUppercase && !current.isEmpty {
                parts.append(current)
                current = String(char)
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

}
