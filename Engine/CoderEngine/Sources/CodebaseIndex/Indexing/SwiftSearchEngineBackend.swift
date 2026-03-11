import Foundation

struct SwiftSearchEngineBackend: SearchEngineBackend {
    let kind: SearchEngineBackendKind = .swift

    func search(
        query: SearchQueryInput,
        snapshot: SemanticIndexSearchSnapshot
    ) -> [SearchHitOutput] {
        let (positiveQuery, negativeTokens) = SemanticSearchQueryParser.splitNegations(query.query)
        let queryTokens = SemanticIndex.tokenizeStatic(positiveQuery)
        guard !queryTokens.isEmpty else { return [] }
        guard !snapshot.chunks.isEmpty else { return [] }

        var scores: [String: Double] = [:]
        for token in Set(queryTokens) {
            guard let postingList = snapshot.invertedIndex[token] else { continue }
            let df = Double(postingList.count)
            let n = Double(snapshot.totalDocs)
            let idf = log((n - df + 0.5) / (df + 0.5) + 1.0)

            for chunkId in postingList {
                if !query.targetDirectories.isEmpty {
                    guard let chunk = snapshot.chunks[chunkId],
                          query.targetDirectories.contains(where: { chunk.filePath.hasPrefix($0) }) else {
                        continue
                    }
                }

                let tf = Double(snapshot.termFrequencies[chunkId]?[token] ?? 0)
                let dl = Double(snapshot.docLengths[chunkId] ?? 1)
                let avgDl = max(snapshot.avgDocLength, 1.0)
                let tfNorm = (tf * (snapshot.k1 + 1))
                    / (tf + snapshot.k1 * (1 - snapshot.b + snapshot.b * dl / avgDl))
                scores[chunkId, default: 0] += idf * tfNorm
            }
        }

        applyBonuses(to: &scores, positiveQuery: positiveQuery, queryTokens: queryTokens, snapshot: snapshot)

        if !negativeTokens.isEmpty {
            let negativeSet = Set(negativeTokens)
            scores = scores.filter { chunkId, _ in
                guard let chunk = snapshot.chunks[chunkId] else { return false }
                let chunkTokens = Set(SemanticIndex.tokenizeStatic(chunk.contextualizedText))
                return negativeSet.isDisjoint(with: chunkTokens)
            }
        }

        return scores
            .sorted { $0.value > $1.value }
            .prefix(query.numResults)
            .map { SearchHitOutput(chunkId: $0.key, score: $0.value) }
    }

    private func applyBonuses(
        to scores: inout [String: Double],
        positiveQuery: String,
        queryTokens: [String],
        snapshot: SemanticIndexSearchSnapshot
    ) {
        let queryLower = positiveQuery.lowercased()
        let queryTokensLower = Set(queryTokens)
        let queryWordsLower = positiveQuery.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        for chunkId in scores.keys {
            guard let chunk = snapshot.chunks[chunkId] else { continue }
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
            var directoryWordHits = 0
            for word in queryWordsLower where word.count >= 3 && dirPath.contains(word) {
                directoryWordHits += 1
                bonus += 0.25
                if directoryWordHits >= 3 { break }
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
                let codeLineCount = chunk.content
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .filter { line in
                        !(line.hasPrefix("//") || line.hasPrefix("/*") || line.hasPrefix("*") || line.hasPrefix("#"))
                    }
                    .count
                if codeLineCount > 0 {
                    bonus += 0.25
                }
            }

            scores[chunkId] = (scores[chunkId] ?? 0) + bonus
        }
    }
}
