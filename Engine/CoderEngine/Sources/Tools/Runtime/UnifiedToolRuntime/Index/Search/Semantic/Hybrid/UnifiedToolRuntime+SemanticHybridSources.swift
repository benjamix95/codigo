import Foundation

extension UnifiedToolRuntime {
    private var grepFallbackCacheMaxEntries: Int { 24 }
    private var grepFallbackCacheTTLSeconds: TimeInterval { 45 }

    func collectHybridSearchHits(
        request: HybridSearchRequest,
        index: CodebaseIndex?
    ) async -> ([HybridSourceHit], String?) {
        var hits: [HybridSourceHit] = []
        if let index {
            async let semanticHits = collectSemanticIndexHits(request: request, index: index)
            async let vectorHits = collectVectorIndexHits(request: request, index: index)
            async let symbolHits = collectSymbolIndexHits(request: request, index: index)
            hits.append(contentsOf: await semanticHits)
            hits.append(contentsOf: await vectorHits)
            hits.append(contentsOf: await symbolHits)
        }
        if let skipReason = grepFallbackSkipReason(indexedHits: hits, request: request) {
            return (hits, skipReason)
        }
        let (grepHits, grepSkipReason) = await collectGrepFallbackHits(request: request)
        hits.append(contentsOf: grepHits)
        return (hits, grepSkipReason)
    }

    func collectSemanticIndexHits(
        request: HybridSearchRequest,
        index: CodebaseIndex
    ) async -> [HybridSourceHit] {
        let results = await index.semanticIndex.search(
            query: request.query,
            targetDirectories: request.targetDirectories,
            numResults: max(20, request.numResults * 3)
        )
        guard !results.isEmpty else { return [] }

        let maxScore = max(results.first?.score ?? 1.0, 1.0)
        return results.enumerated().map { idx, result in
            let chunk = result.chunk
            let confidence = max(0.05, min(1.0, result.score / maxScore))
            let snippet = firstMeaningfulSnippet(from: chunk.content)
            return HybridSourceHit(
                key: buildHitKey(filePath: chunk.filePath, lineStart: chunk.startLine),
                source: .semanticIndex,
                rank: idx + 1,
                sourceScore: result.score,
                sourceConfidence: confidence,
                filePath: chunk.filePath,
                lineStart: chunk.startLine,
                lineEnd: chunk.endLine,
                scope: chunk.scope,
                snippet: snippet
            )
        }
    }

    func collectSymbolIndexHits(
        request: HybridSearchRequest,
        index: CodebaseIndex
    ) async -> [HybridSourceHit] {
        var candidates: [IndexedSymbol] = await index.findSymbols(query: request.query, kind: nil, limit: max(30, request.numResults * 3))
        for token in request.queryTokens where token.count >= 3 {
            let tokenMatches = await index.findSymbols(query: token, kind: nil, limit: request.numResults)
            candidates.append(contentsOf: tokenMatches)
        }

        let allowedScopePrefixes = buildAllowedScopePrefixes(
            searchPaths: request.searchPaths,
            workspacePaths: request.workspacePaths
        )
        if !allowedScopePrefixes.isEmpty {
            candidates = candidates.filter { symbol in
                isRelativePath(symbol.filePath, withinAnyPrefix: allowedScopePrefixes)
                    || isAbsolutePath(symbol.filePath, withinAnySearchPath: request.searchPaths)
            }
        }

        var seen = Set<String>()
        var deduped: [IndexedSymbol] = []
        for symbol in candidates where seen.insert(symbol.id).inserted {
            deduped.append(symbol)
        }

        let queryLower = request.query.lowercased()
        let ranked = deduped
            .map { symbol -> (IndexedSymbol, Double) in
                let nameLower = symbol.name.lowercased()
                let signatureLower = symbol.signature.lowercased()
                var score = 0.3
                if nameLower == queryLower { score += 1.0 }
                if nameLower.hasPrefix(queryLower) { score += 0.7 }
                if nameLower.contains(queryLower) { score += 0.5 }
                for token in request.queryTokens where token.count >= 3 {
                    if nameLower.contains(token) { score += 0.25 }
                    if signatureLower.contains(token) { score += 0.1 }
                }
                if symbol.kind.isType { score += 0.15 }
                return (symbol, min(2.5, score))
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lhs.0.filePath != rhs.0.filePath { return lhs.0.filePath < rhs.0.filePath }
                return lhs.0.line < rhs.0.line
            }
            .prefix(max(20, request.numResults * 2))

        return ranked.enumerated().map { idx, item in
            let symbol = item.0
            let confidence = min(1.0, item.1 / 2.5)
            return HybridSourceHit(
                key: buildHitKey(filePath: symbol.filePath, lineStart: symbol.line),
                source: .symbolIndex,
                rank: idx + 1,
                sourceScore: item.1,
                sourceConfidence: confidence,
                filePath: symbol.filePath,
                lineStart: symbol.line,
                lineEnd: max(symbol.endLine, symbol.line),
                scope: symbol.qualifiedName,
                snippet: symbol.signature
            )
        }
    }

    func collectGrepFallbackHits(
        request: HybridSearchRequest
    ) async -> ([HybridSourceHit], String?) {
        if request.strictScope && request.targetDirectories.isEmpty {
            return ([], "strict_scope_no_target_directories")
        }
        if request.queryTokens.count <= 1 && request.searchPaths.count > 8 {
            return ([], "circuit_breaker_wide_scope_short_query")
        }

        let patterns = buildGrepPatterns(queryTokens: request.queryTokens)
        guard !patterns.isEmpty else { return ([], nil) }

        let cacheKey = grepFallbackCacheKey(for: request, patterns: patterns)
        if let cached = cachedGrepFallbackHits(forKey: cacheKey, now: .now) {
            return (cached, nil)
        }

        var hits: [HybridSourceHit] = []
        var seenKeys = Set<String>()
        let constrainedSearchPaths = Array(request.searchPaths.prefix(20))
        let grepTimeoutMs = grepTimeoutMs(
            searchPathCount: constrainedSearchPaths.count,
            tokenCount: request.queryTokens.count
        )
        for pattern in patterns.prefix(5) {
            for searchPath in constrainedSearchPaths {
                guard FileManager.default.fileExists(atPath: searchPath) else { continue }
                let workspace = workspaceRootForSearchPath(
                    searchPath,
                    workspacePaths: request.workspacePaths
                ) ?? searchPath
                let output = await runSemanticTextSearch(
                    pattern: pattern,
                    searchPath: searchPath,
                    workspace: workspace,
                    timeoutMs: grepTimeoutMs
                )
                guard !output.isEmpty else { continue }
                for line in output.components(separatedBy: "\n") where !line.isEmpty {
                    let parts = line.split(separator: ":", maxSplits: 2).map(String.init)
                    guard parts.count >= 3 else { continue }
                    let absolutePath = parts[0]
                    let lineNum = Int(parts[1]) ?? 0
                    guard lineNum > 0 else { continue }
                    let snippet = parts[2].trimmingCharacters(in: .whitespaces)
                    let relative = relativePathForDisplay(
                        absolutePath: absolutePath,
                        workspacePaths: request.workspacePaths
                    )
                    let confidence = grepConfidence(snippet: snippet, queryTokens: request.queryTokens)
                    let key = buildHitKey(filePath: relative, lineStart: lineNum)
                    guard seenKeys.insert(key).inserted else { continue }
                    hits.append(
                        HybridSourceHit(
                            key: key,
                            source: .grepFallback,
                            rank: hits.count + 1,
                            sourceScore: confidence,
                            sourceConfidence: confidence,
                            filePath: relative,
                            lineStart: lineNum,
                            lineEnd: lineNum,
                            scope: "",
                            snippet: snippet
                        ))
                    if hits.count >= max(40, request.numResults * 4) {
                        putGrepFallbackCache(hits, forKey: cacheKey, now: .now)
                        return (hits, nil)
                    }
                }
            }
        }
        putGrepFallbackCache(hits, forKey: cacheKey, now: .now)
        return (hits, nil)
    }

    func buildGrepPatterns(queryTokens: [String]) -> [String] {
        guard !queryTokens.isEmpty else { return [] }
        var patterns: [String] = []
        if queryTokens.count >= 2 {
            patterns.append(queryTokens.joined(separator: ".*"))
            let camel = queryTokens[0] + queryTokens.dropFirst().map(\.capitalized).joined()
            let pascal = queryTokens.map(\.capitalized).joined()
            patterns.append(camel)
            patterns.append(pascal)
            patterns.append(queryTokens.joined(separator: "_"))
        }
        patterns.append(contentsOf: queryTokens.filter { $0.count >= 2 })
        var deduped: [String] = []
        var seen = Set<String>()
        for pattern in patterns where seen.insert(pattern).inserted {
            deduped.append(pattern)
        }
        return deduped
    }

    func grepConfidence(snippet: String, queryTokens: [String]) -> Double {
        let text = snippet.lowercased()
        guard !queryTokens.isEmpty else { return 0.1 }
        let uniqueTokens = Array(Set(queryTokens))
        let matchedTokens = uniqueTokens.filter { text.contains($0) }
        let matchRatio = Double(matchedTokens.count) / Double(max(1, uniqueTokens.count))
        var score = 0.1 + (matchRatio * 0.55)

        if uniqueTokens.count >= 2 {
            let phrase = uniqueTokens.joined(separator: " ")
            if text.contains(phrase) {
                score += 0.18
            }
        }

        if text.contains("func ") || text.contains("class ") || text.contains("struct ")
            || text.contains("protocol ") || text.contains("enum ")
            || text.contains("def ") || text.contains("function ")
        {
            score += 0.2
        }

        // Penalize overlong snippets that usually come from noisy minified or log lines.
        let length = text.count
        if length > 220 {
            score -= min(0.20, Double(length - 220) / 2_000.0)
        } else if length < 120 {
            score += 0.05
        }

        return max(0.05, min(1.0, score))
    }

    func firstMeaningfulSnippet(from content: String) -> String {
        let lines = content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.first ?? ""
    }

    func relativePathForDisplay(absolutePath: String, workspacePaths: [String]) -> String {
        let normalized = (absolutePath as NSString).standardizingPath
        for root in workspacePaths {
            let rootNorm = (root as NSString).standardizingPath
            if normalized == rootNorm { return (root as NSString).lastPathComponent }
            let prefix = rootNorm.hasSuffix("/") ? rootNorm : rootNorm + "/"
            if normalized.hasPrefix(prefix) {
                let tail = String(normalized.dropFirst(prefix.count))
                return ((root as NSString).lastPathComponent) + "/" + tail
            }
        }
        return normalized
    }

    func buildHitKey(filePath: String, lineStart: Int) -> String {
        "\(filePath):\(max(1, lineStart))"
    }

    private func buildAllowedScopePrefixes(searchPaths: [String], workspacePaths: [String]) -> [String] {
        guard !searchPaths.isEmpty else { return [] }
        var prefixes: [String] = []
        var seen = Set<String>()
        for path in searchPaths {
            let relative = relativePathForDisplay(
                absolutePath: path,
                workspacePaths: workspacePaths
            )
            if seen.insert(relative).inserted {
                prefixes.append(relative)
            }
        }
        return prefixes
    }

    private func isRelativePath(_ filePath: String, withinAnyPrefix prefixes: [String]) -> Bool {
        let normalized = (filePath as NSString).standardizingPath
        for prefix in prefixes {
            if normalized == prefix { return true }
            if normalized.hasPrefix(prefix + "/") { return true }
        }
        return false
    }

    private func isAbsolutePath(_ filePath: String, withinAnySearchPath searchPaths: [String]) -> Bool {
        guard (filePath as NSString).isAbsolutePath else { return false }
        let normalized = URL(fileURLWithPath: filePath).standardizedFileURL.path
        for scope in searchPaths {
            let scopeNorm = URL(fileURLWithPath: scope).standardizedFileURL.path
            if normalized == scopeNorm { return true }
            let prefix = scopeNorm.hasSuffix("/") ? scopeNorm : scopeNorm + "/"
            if normalized.hasPrefix(prefix) { return true }
        }
        return false
    }

    private func workspaceRootForSearchPath(_ searchPath: String, workspacePaths: [String]) -> String? {
        let normalized = URL(fileURLWithPath: searchPath).standardizedFileURL.path
        let sortedRoots = workspacePaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .sorted { $0.count > $1.count }
        for root in sortedRoots {
            if normalized == root { return root }
            let prefix = root.hasSuffix("/") ? root : root + "/"
            if normalized.hasPrefix(prefix) { return root }
        }
        return nil
    }

    private func grepTimeoutMs(searchPathCount: Int, tokenCount: Int) -> Int {
        let boundedPaths = min(max(searchPathCount, 1), 20)
        let boundedTokens = min(max(tokenCount, 1), 12)
        let base = 3_500
        let pathFactor = boundedPaths * 450
        let tokenFactor = boundedTokens * 220
        return min(15_000, base + pathFactor + tokenFactor)
    }

    private func grepFallbackCacheKey(for request: HybridSearchRequest, patterns: [String]) -> String {
        let scope = request.searchPaths.sorted().joined(separator: "|")
        let normalizedPatterns = patterns.sorted().joined(separator: "|")
        return "\(request.query.lowercased())::\(scope)::\(normalizedPatterns)::strict=\(request.strictScope)"
    }

    private func cachedGrepFallbackHits(forKey key: String, now: Date) -> [HybridSourceHit]? {
        guard let cached = grepFallbackCache[key] else { return nil }
        if now.timeIntervalSince(cached.createdAt) > grepFallbackCacheTTLSeconds {
            grepFallbackCache.removeValue(forKey: key)
            grepFallbackCacheOrder.removeAll { $0 == key }
            return nil
        }
        grepFallbackCacheOrder.removeAll { $0 == key }
        grepFallbackCacheOrder.append(key)
        return cached.hits
    }

    private func putGrepFallbackCache(_ hits: [HybridSourceHit], forKey key: String, now: Date) {
        guard !hits.isEmpty else { return }
        grepFallbackCache[key] = (hits: hits, createdAt: now)
        grepFallbackCacheOrder.removeAll { $0 == key }
        grepFallbackCacheOrder.append(key)
        while grepFallbackCacheOrder.count > grepFallbackCacheMaxEntries {
            let evicted = grepFallbackCacheOrder.removeFirst()
            grepFallbackCache.removeValue(forKey: evicted)
        }
    }
}
