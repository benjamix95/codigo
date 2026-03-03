import Foundation

extension CodebaseIndex {

    /// Complete codebase statistics
    public func stats() -> FileStats {
        let files = allFileNodes.values.filter { $0.kind == .file }
        let dirs = allFileNodes.values.filter { $0.kind == .directory }

        // Language breakdown
        var langCount: [FileLanguage: Int] = [:]
        for file in files where file.isSourceFile {
            langCount[file.language, default: 0] += 1
        }

        // Largest files
        let largest =
            files
            .sorted { $0.size > $1.size }
            .prefix(10)
            .map { (path: $0.relativePath, size: $0.size) }

        // Deepest path
        let deepest =
            files
            .max(by: { $0.depth < $1.depth })
            .map { (path: $0.relativePath, depth: $0.depth) }

        let totalSize = files.reduce(UInt64(0)) { $0 + $1.size }

        return FileStats(
            totalFiles: files.count,
            totalDirectories: dirs.count,
            totalSize: totalSize,
            languageBreakdown: langCount,
            largestFiles: largest,
            deepestPath: deepest
        )
    }

    /// Current index status
    public func status() -> IndexStatusInfo {
        let progress: IndexingProgress?
        if let p = _indexingProgress {
            progress = IndexingProgress(current: p.current, total: p.total)
        } else {
            progress = nil
        }
        return IndexStatusInfo(
            status: _status,
            totalFiles: allFileNodes.count,
            totalSourceFiles: indexedFiles.count,
            totalSymbols: totalSymbolsExtracted,
            lastIndexedAt: lastFullIndexAt,
            indexDurationMs: indexDurationMs,
            workspacePaths: currentWorkspacePaths.map(\.path),
            progress: progress
        )
    }

    /// Suspends until the index status is `.ready`, or until the timeout elapses.
    /// Uses exponential backoff polling (10ms → 500ms).
    /// Works thanks to actor reentrancy: `Task.sleep` releases the executor,
    /// allowing `indexWorkspace()` to proceed during the sleep.
    /// Returns `true` if the index became ready, `false` on timeout.
    public func waitUntilReady(timeoutMs: Int = 30_000) async -> Bool {
        if _status == .ready { return true }
        guard _status == .indexing else { return false }

        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        var sleepNs: UInt64 = 10_000_000  // start at 10ms
        while _status == .indexing, Date() < deadline {
            try? await Task.sleep(nanoseconds: sleepNs)
            sleepNs = min(sleepNs * 2, 500_000_000)  // cap at 500ms
        }
        return _status == .ready
    }

    /// Index summary in text format (for LLM context)
    public func summaryText() -> String {
        let info = IndexStatusInfo(
            status: _status,
            totalFiles: allFileNodes.count,
            totalSourceFiles: indexedFiles.count,
            totalSymbols: totalSymbolsExtracted,
            lastIndexedAt: lastFullIndexAt,
            indexDurationMs: indexDurationMs,
            workspacePaths: currentWorkspacePaths.map(\.path),
            progress: nil
        )

        var lines: [String] = []
        lines.append("## Codebase Index")
        lines.append("Status: \(info.status.rawValue)")
        lines.append("Files: \(info.totalFiles) total, \(info.totalSourceFiles) source")
        lines.append("Symbols: \(info.totalSymbols)")
        if let date = info.lastIndexedAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            lines.append(
                "Last indexed: \(formatter.string(from: date)) (\(info.indexDurationMs)ms)")
        }

        let langBreakdown = languageBreakdown()
        if !langBreakdown.isEmpty {
            lines.append(
                "Languages: "
                    + langBreakdown.prefix(5).map { "\($0.key.rawValue): \($0.value)" }.joined(
                        separator: ", "))
        }

        // Top-level types
        let types = allTypes(limit: 20)
        if !types.isEmpty {
            lines.append("Main types: " + types.prefix(15).map(\.name).joined(separator: ", "))
        }

        return lines.joined(separator: "\n")
    }

    /// Returns the list of all indexed files
    public func allIndexedFilePaths() -> [String] {
        return Array(indexedFiles.keys).sorted()
    }

    /// Returns a specific IndexedFile
    public func getIndexedFile(_ relativePath: String) -> IndexedFile? {
        return indexedFiles[relativePath]
    }

    /// Returns a specific FileNode
    public func getFileNode(_ relativePath: String) -> FileNode? {
        return allFileNodes[relativePath]
    }

    /// Advanced search: semantic grep using the index
    public func semanticGrep(
        query: String,
        filePattern: String? = nil,
        symbolKinds: [SymbolKind]? = nil,
        accessLevels: [AccessLevel]? = nil,
        limit: Int = 50
    ) -> [IndexedSymbol] {
        let queryLower = query.lowercased()
        var results: [IndexedSymbol] = []

        let allSymbols: [IndexedSymbol]
        if let kinds = symbolKinds {
            allSymbols = kinds.flatMap { symbolsByKind[$0] ?? [] }
        } else {
            allSymbols = Array(symbolsByName.values.flatMap { $0 })
        }

        for symbol in allSymbols {
            // Filter by access level
            if let levels = accessLevels, !levels.contains(symbol.accessLevel) {
                continue
            }

            // Filter by file pattern
            if let pattern = filePattern {
                let patternLower = pattern.lowercased()
                if !symbol.filePath.lowercased().contains(patternLower)
                    && !matchGlob(pattern: patternLower, path: symbol.filePath.lowercased())
                {
                    continue
                }
            }

            // Match against name, qualified name, signature, documentation
            let searchTargets = [
                symbol.name.lowercased(),
                symbol.qualifiedName.lowercased(),
                symbol.signature.lowercased(),
                symbol.documentation?.lowercased() ?? "",
            ]

            let matches = searchTargets.contains { $0.contains(queryLower) }
            if matches {
                results.append(symbol)
                if results.count >= limit { break }
            }
        }

        // Sort: exact name match first, then prefix, then contains
        results.sort { a, b in
            let aName = a.name.lowercased()
            let bName = b.name.lowercased()
            if aName == queryLower && bName != queryLower { return true }
            if bName == queryLower && aName != queryLower { return false }
            if aName.hasPrefix(queryLower) && !bName.hasPrefix(queryLower) { return true }
            if bName.hasPrefix(queryLower) && !aName.hasPrefix(queryLower) { return false }
            return aName < bName
        }

        return Array(results.prefix(limit))
    }
}
