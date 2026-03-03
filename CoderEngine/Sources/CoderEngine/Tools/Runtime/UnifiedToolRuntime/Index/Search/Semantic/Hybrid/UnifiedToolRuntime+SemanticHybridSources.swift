import Foundation

extension UnifiedToolRuntime {
    func collectHybridSearchHits(
        request: HybridSearchRequest,
        index: CodebaseIndex?
    ) async -> [HybridSourceHit] {
        var hits: [HybridSourceHit] = []
        if let index {
            hits.append(contentsOf: await collectSemanticIndexHits(request: request, index: index))
            hits.append(contentsOf: await collectSymbolIndexHits(request: request, index: index))
        }
        hits.append(contentsOf: await collectGrepFallbackHits(request: request))
        return hits
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
    ) async -> [HybridSourceHit] {
        let patterns = buildGrepPatterns(queryTokens: request.queryTokens)
        guard !patterns.isEmpty else { return [] }

        var hits: [HybridSourceHit] = []
        var seenKeys = Set<String>()
        for pattern in patterns.prefix(5) {
            for searchPath in request.searchPaths {
                guard FileManager.default.fileExists(atPath: searchPath) else { continue }
                let workspace = workspaceRootForSearchPath(
                    searchPath,
                    workspacePaths: request.workspacePaths
                ) ?? searchPath
                let output = await runSemanticTextSearch(
                    pattern: pattern,
                    searchPath: searchPath,
                    workspace: workspace
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
                        return hits
                    }
                }
            }
        }
        return hits
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
        var score = 0.2
        for token in queryTokens where text.contains(token) { score += 0.15 }
        if text.contains("func ") || text.contains("class ") || text.contains("struct ")
            || text.contains("protocol ") || text.contains("enum ")
            || text.contains("def ") || text.contains("function ")
        {
            score += 0.2
        }
        return min(1.0, score)
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
}
