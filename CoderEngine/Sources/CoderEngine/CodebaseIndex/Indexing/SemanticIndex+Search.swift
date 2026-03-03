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
        let queryTokens = tokenize(query)
        guard !queryTokens.isEmpty else {
            Self.logger.debug("search: empty query tokens for '\(query, privacy: .public)'")
            return []
        }

        if chunks.isEmpty {
            Self.logger.notice("search: index is empty (0 chunks), query='\(query, privacy: .public)'")
            return []
        }

        var scores: [String: Double] = [:]
        for token in Set(queryTokens) {
            guard let postingList = invertedIndex[token] else { continue }
            let df = Double(postingList.count)
            let n = Double(totalDocs)
            let idf = log((n - df + 0.5) / (df + 0.5) + 1.0)

            for chunkId in postingList {
                if !targetDirectories.isEmpty {
                    guard let chunk = chunks[chunkId],
                          targetDirectories.contains(where: { chunk.filePath.hasPrefix($0) }) else {
                        continue
                    }
                }

                let tf = Double(termFrequencies[chunkId]?[token] ?? 0)
                let dl = Double(docLengths[chunkId] ?? 1)
                let avgDl = max(avgDocLength, 1.0)
                let tfNorm = (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * dl / avgDl))
                scores[chunkId, default: 0] += idf * tfNorm
            }
        }

        let queryLower = query.lowercased()
        let queryTokensLower = Set(queryTokens)
        let queryWordsLower = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        for (chunkId, _) in scores {
            guard let chunk = chunks[chunkId] else { continue }
            var bonus = 0.0

            for sym in chunk.symbolNames {
                let symLower = sym.lowercased()
                if symLower == queryLower {
                    bonus += 10.0
                } else if symLower.contains(queryLower) {
                    bonus += 5.0
                }
                for token in queryTokensLower where token.count >= 3 && symLower.contains(token) {
                    bonus += 1.5
                }
            }

            let scopeLower = chunk.scope.lowercased()
            for token in queryTokensLower where scopeLower.contains(token) {
                bonus += 1.0
            }

            let fileNameLower = (chunk.filePath as NSString).lastPathComponent.lowercased()
            let fileNameNoExt = (fileNameLower as NSString).deletingPathExtension
            for word in queryWordsLower where word.count >= 3 {
                if fileNameNoExt == word {
                    bonus += 4.0
                } else if fileNameNoExt.contains(word) {
                    bonus += 2.0
                }
            }

            let dirPath = (chunk.filePath as NSString).deletingLastPathComponent.lowercased()
            for word in queryWordsLower where word.count >= 3 && dirPath.contains(word) {
                bonus += 0.8
            }

            switch chunk.kind {
            case "class", "struct", "protocol", "enum", "interface":
                bonus += 1.0
            case "function", "method":
                bonus += 0.5
            case "property", "constant":
                bonus += 0.2
            default:
                break
            }

            let contentLower = chunk.content.lowercased()
            if contentLower.contains("///") || contentLower.contains("/**") || contentLower.contains("# ") {
                bonus += 0.3
            }

            scores[chunkId] = (scores[chunkId] ?? 0) + bonus
        }

        let ranked = scores
            .sorted { $0.value > $1.value }
            .prefix(numResults)
            .compactMap { (chunkId, score) -> SearchResult? in
                guard let chunk = chunks[chunkId] else { return nil }
                return SearchResult(chunk: chunk, score: score)
            }

        return Array(ranked)
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

    // MARK: - Tokenization

    func tokenize(_ text: String) -> [String] {
        Self.tokenizeStatic(text)
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
        var expanded = filtered
        for token in filtered where expanded.count < 3000 {
            if let syns = Self.synonymMap[token] {
                expanded.append(contentsOf: syns.prefix(2))
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
