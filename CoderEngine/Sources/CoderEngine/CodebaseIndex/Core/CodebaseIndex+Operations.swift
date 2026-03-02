import Foundation
import os

extension CodebaseIndex {
    // MARK: - Public API: Indexing

    /// Index the complete workspace (full scan)
    public func indexWorkspace(
        paths: [URL],
        excludedPaths: [String] = [],
        excludedFilePatterns: [String] = [],
        respectGitignore: Bool = true
    ) async -> IndexResult {
        let startTime = Date()
        _status = .indexing
        Self.logger.info("indexWorkspace: starting full index for \(paths.map(\.path).joined(separator: ", "), privacy: .public)")

        self.currentWorkspacePaths = paths
        self.excludedPaths = excludedPaths
        self.excludedFilePatterns = excludedFilePatterns
        self.respectGitignore = respectGitignore

        // Load .gitignore rules if enabled
        if respectGitignore, let firstRoot = paths.first {
            loadGitignoreRules(for: firstRoot)
        } else {
            gitignoreRules = []
        }

        // Reset state
        fileTrees.removeAll()
        indexedFiles.removeAll()
        symbolsByName.removeAll()
        symbolsByFile.removeAll()
        symbolsByKind.removeAll()
        allFileNodes.removeAll()
        importGraph.removeAll()
        reverseImportGraph.removeAll()
        contentHashes.removeAll()

        totalFilesScanned = 0
        totalSymbolsExtracted = 0

        // 1. Build file tree for each root
        for rootURL in paths {
            let tree = buildFileTree(
                at: rootURL,
                relativePath: "",
                depth: 0
            )
            fileTrees[rootURL.path] = tree

            // Flatten all file nodes
            flattenNodes(tree)
        }

        // 2. Index source files (extract symbols)
        let sourceFiles = allFileNodes.values.filter {
            $0.isSourceFile && $0.size <= Self.maxFileSize
            && !isFileExcluded($0.relativePath)
            && !isGitignored($0.relativePath, isDirectory: false)
        }
        let filesToIndex = Array(sourceFiles.prefix(Self.maxFiles))
        let totalToIndex = filesToIndex.count
        _indexingProgress = (current: 0, total: totalToIndex)

        // Parallelize symbol extraction: SymbolExtractor.indexFileWithContent is a
        // pure static function (file read + regex), safe to run concurrently.
        // We capture file content here to avoid double I/O in the semantic index phase.
        var contentCache: [String: String] = [:]
        let batchSize = 64
        for batchStart in stride(from: 0, to: filesToIndex.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, filesToIndex.count)
            let batch = filesToIndex[batchStart..<batchEnd]

            let results: [(IndexedFile, String)] = await withTaskGroup(
                of: (IndexedFile, String)?.self,
                returning: [(IndexedFile, String)].self
            ) { group in
                for node in batch {
                    group.addTask {
                        SymbolExtractor.indexFileWithContent(
                            absolutePath: node.absolutePath,
                            relativePath: node.relativePath,
                            language: node.language
                        )
                    }
                }
                var collected: [(IndexedFile, String)] = []
                for await result in group {
                    if let pair = result {
                        collected.append(pair)
                    }
                }
                return collected
            }

            // Merge results sequentially (actor-isolated mutations)
            for (indexed, content) in results {
                addIndexedFile(indexed)
                contentCache[indexed.absolutePath] = content
                totalFilesScanned += 1
            }
            _indexingProgress = (current: batchEnd, total: totalToIndex)
        }

        // 3. Build import graph
        buildImportGraph()

        // 4. Build semantic index (BM25 + AST chunking)
        // Configure persistence and try loading cached data
        let cacheDir = Self.cacheDirectory(for: paths)
        let semanticCachePath = cacheDir.appendingPathComponent("semantic.jsonl")
        await semanticIndex.setPersistencePath(semanticCachePath)

        let allIndexed = Array(indexedFiles.values)
        if let firstRoot = paths.first {
            // Try loading persisted semantic index
            let semanticStatus = await semanticIndex.status()
            if semanticStatus.totalChunks == 0 {
                await semanticIndex.loadFromDisk()
            }

            // Validate persisted data with Merkle tree simHash
            let loadedStatus = await semanticIndex.status()
            if loadedStatus.totalChunks > 0 {
                let newMerkle = MerkleTree.build(root: firstRoot)
                let newSimHash = newMerkle.map { MerkleTree.simHash(of: $0) } ?? 0
                if loadedStatus.simHash == newSimHash && newSimHash != 0 {
                    Self.logger.info("indexWorkspace: reusing persisted semantic index (\(loadedStatus.totalChunks) chunks, simHash match)")
                } else {
                    Self.logger.info("indexWorkspace: persisted semantic index stale, rebuilding")
                    await semanticIndex.buildIndex(indexedFiles: allIndexed, workspaceRoot: firstRoot, contentCache: contentCache)
                }
            } else {
                await semanticIndex.buildIndex(indexedFiles: allIndexed, workspaceRoot: firstRoot, contentCache: contentCache)
            }
        }

        _indexingProgress = nil
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        indexDurationMs = durationMs
        lastFullIndexAt = Date()
        _status = .ready

        Self.logger.info("indexWorkspace: completed — \(self.totalSymbolsExtracted) symbols, \(self.totalFilesScanned) files, \(durationMs)ms")

        return IndexResult(
            totalFiles: allFileNodes.count,
            totalSourceFiles: filesToIndex.count,
            totalSymbols: totalSymbolsExtracted,
            totalDirectories: fileTrees.values.reduce(0) { acc, tree in
                acc + countDirectories(tree)
            },
            durationMs: durationMs,
            languages: languageBreakdown()
        )
    }

    /// Incremental indexing: re-indexes only modified files
    public func incrementalUpdate() async -> IndexResult {
        let startTime = Date()
        _status = .indexing
        Self.logger.info("incrementalUpdate: starting")

        var updatedCount = 0
        var removedCount = 0
        var changedFiles: [IndexedFile] = []

        // Rebuild file trees from disk to avoid stale file nodes.
        fileTrees.removeAll()
        allFileNodes.removeAll()
        for rootURL in currentWorkspacePaths {
            let tree = buildFileTree(at: rootURL, relativePath: "", depth: 0)
            fileTrees[rootURL.path] = tree
            flattenNodes(tree)
        }

        let sourceNodes = allFileNodes.filter { _, node in
            node.isSourceFile && node.size <= Self.maxFileSize
        }

        let currentSourcePaths = Set(sourceNodes.keys)
        let indexedPaths = Set(indexedFiles.keys)
        let removedPaths = indexedPaths.subtracting(currentSourcePaths)
        for relativePath in removedPaths {
            removeIndexedFile(relativePath)
            removedCount += 1
        }

        for (relativePath, node) in sourceNodes {
            guard node.isSourceFile, node.size <= Self.maxFileSize else { continue }

            // Check if file was modified
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: node.absolutePath),
                let modDate = attrs[.modificationDate] as? Date
            else { continue }

            let existingFile = indexedFiles[relativePath]
            if let existing = existingFile, existing.indexedAt >= modDate {
                continue  // File not modified since last index
            }

            // Check content hash
            if let data = FileManager.default.contents(atPath: node.absolutePath) {
                let hash = SymbolExtractor.fnv1aHash(data)
                if let existingHash = contentHashes[node.absolutePath], existingHash == hash {
                    continue  // Content unchanged
                }
            }

            // Re-index this file
            removeIndexedFile(relativePath)

            if let indexed = SymbolExtractor.indexFile(
                absolutePath: node.absolutePath,
                relativePath: relativePath,
                language: node.language
            ) {
                addIndexedFile(indexed)
                updatedCount += 1
                changedFiles.append(indexed)
            }
        }

        // Re-build import graph
        buildImportGraph()

        // Update semantic index incrementally (not a full rebuild)
        if let firstRoot = currentWorkspacePaths.first {
            if !changedFiles.isEmpty {
                await semanticIndex.incrementalUpdate(
                    changedFiles: changedFiles,
                    workspaceRoot: firstRoot
                )
            }
            for relativePath in removedPaths {
                await semanticIndex.removeFile(relativePath)
            }
        } else if !changedFiles.isEmpty || removedCount > 0 {
            await semanticIndex.clear()
        }

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        indexDurationMs = durationMs
        _status = .ready

        Self.logger.info("incrementalUpdate: completed — \(updatedCount) updated, \(removedCount) removed, \(durationMs)ms")

        return IndexResult(
            totalFiles: allFileNodes.count,
            totalSourceFiles: indexedFiles.count,
            totalSymbols: totalSymbolsExtracted,
            totalDirectories: fileTrees.values.reduce(0) { acc, tree in
                acc + countDirectories(tree)
            },
            durationMs: durationMs,
            languages: languageBreakdown(),
            updatedFiles: updatedCount + removedCount
        )
    }

    /// Index a single file (for real-time updates)
    public func indexSingleFile(absolutePath: String, relativePath: String) async {
        let canonicalRelativePath = canonicalRelativePath(for: absolutePath) ?? relativePath

        // Remove old entry
        removeIndexedFile(canonicalRelativePath)

        if let attrs = try? FileManager.default.attributesOfItem(atPath: absolutePath) {
            let ext = (absolutePath as NSString).pathExtension.lowercased()
            let size = attrs[.size] as? UInt64 ?? 0
            let modDate = attrs[.modificationDate] as? Date ?? .distantPast
            let depth = canonicalRelativePath.split(separator: "/").count - 1
            let node = FileNode(
                name: (absolutePath as NSString).lastPathComponent,
                kind: .file,
                extension_: ext.isEmpty ? nil : ext,
                relativePath: canonicalRelativePath,
                absolutePath: absolutePath,
                depth: max(0, depth),
                size: size,
                modifiedAt: modDate
            )
            allFileNodes[canonicalRelativePath] = node
        }

        // Re-index
        if let indexed = SymbolExtractor.indexFile(
            absolutePath: absolutePath,
            relativePath: canonicalRelativePath
        ) {
            addIndexedFile(indexed)
            // Update semantic index for this file.
            await semanticIndex.updateFile(indexed)
        }
    }

    /// Remove a single file from the index (for real-time delete/rename updates).
    public func removeSingleFile(absolutePath: String, relativePath: String? = nil) async {
        let canonicalRelativePath = relativePath ?? canonicalRelativePath(for: absolutePath)
        guard let canonicalRelativePath else { return }

        removeIndexedFile(canonicalRelativePath)
        allFileNodes.removeValue(forKey: canonicalRelativePath)
        await semanticIndex.removeFile(canonicalRelativePath)
    }

    /// Resolve an absolute path to the internal relative path format used by the index.
    public func canonicalRelativePath(for absolutePath: String) -> String? {
        for rootURL in currentWorkspacePaths {
            let rootPath = rootURL.path
            if absolutePath == rootPath {
                return rootURL.lastPathComponent
            }
            let rootWithSlash = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            if absolutePath.hasPrefix(rootWithSlash) {
                let tail = String(absolutePath.dropFirst(rootWithSlash.count))
                let rootName = rootURL.lastPathComponent
                return tail.isEmpty ? rootName : "\(rootName)/\(tail)"
            }
        }
        return nil
    }

    /// Clear all index state and reset status to idle.
    public func clear() async {
        fileTrees.removeAll()
        indexedFiles.removeAll()
        symbolsByName.removeAll()
        symbolsByFile.removeAll()
        symbolsByKind.removeAll()
        allFileNodes.removeAll()
        importGraph.removeAll()
        reverseImportGraph.removeAll()
        contentHashes.removeAll()
        currentWorkspacePaths.removeAll()
        excludedPaths.removeAll()
        totalFilesScanned = 0
        totalSymbolsExtracted = 0
        indexDurationMs = 0
        lastFullIndexAt = nil
        _status = .idle
        await semanticIndex.clear()
    }

    // MARK: - Public API: Symbol Search

    /// Search symbols by name (fuzzy match)
    public func findSymbols(
        query: String,
        kind: SymbolKind? = nil,
        fileFilter: String? = nil,
        limit: Int = 50
    ) -> [IndexedSymbol] {
        let queryLower = query.lowercased()
        var results: [IndexedSymbol] = []

        // Exact match first
        if let exact = symbolsByName[queryLower] {
            results.append(contentsOf: exact)
        }

        // Prefix match
        for (name, symbols) in symbolsByName {
            if name.hasPrefix(queryLower) && name != queryLower {
                results.append(contentsOf: symbols)
            }
        }

        // Contains match (if few results so far)
        if results.count < limit {
            for (name, symbols) in symbolsByName {
                if name.contains(queryLower) && !name.hasPrefix(queryLower) {
                    results.append(contentsOf: symbols)
                }
            }
        }

        // Fuzzy match (subsequence) if still few results
        if results.count < limit / 2 {
            for (name, symbols) in symbolsByName {
                if !name.contains(queryLower) && fuzzyMatch(query: queryLower, target: name) {
                    results.append(contentsOf: symbols)
                }
            }
        }

        // Apply filters
        if let kind = kind {
            results = results.filter { $0.kind == kind }
        }
        if let fileFilter = fileFilter {
            let filterLower = fileFilter.lowercased()
            results = results.filter { $0.filePath.lowercased().contains(filterLower) }
        }

        // Deduplicate
        var seen = Set<String>()
        results = results.filter { seen.insert($0.id).inserted }

        // Sort by relevance
        results.sort { a, b in
            let aName = a.name.lowercased()
            let bName = b.name.lowercased()
            // Exact match first
            if aName == queryLower && bName != queryLower { return true }
            if bName == queryLower && aName != queryLower { return false }
            // Prefix match
            if aName.hasPrefix(queryLower) && !bName.hasPrefix(queryLower) { return true }
            if bName.hasPrefix(queryLower) && !aName.hasPrefix(queryLower) { return false }
            // Public over private
            if a.accessLevel > b.accessLevel { return true }
            if b.accessLevel > a.accessLevel { return false }
            // Types before functions
            if a.kind.isType && !b.kind.isType { return true }
            if b.kind.isType && !a.kind.isType { return false }
            // Shorter name first
            return aName.count < bName.count
        }

        return Array(results.prefix(limit))
    }

    /// Search for a symbol by exact name and type
    public func findExactSymbol(name: String, kind: SymbolKind? = nil) -> [IndexedSymbol] {
        let key = name.lowercased()
        guard let candidates = symbolsByName[key] else { return [] }
        if let kind = kind {
            return candidates.filter { $0.kind == kind }
        }
        return candidates
    }

    /// List all symbols in a file
    public func symbolsInFile(_ relativePath: String) -> [IndexedSymbol] {
        return symbolsByFile[relativePath] ?? []
    }

    /// List all types (class, struct, enum, protocol, interface, trait) in the codebase
    public func allTypes(limit: Int = 200) -> [IndexedSymbol] {
        let typeKinds: [SymbolKind] = [.class, .struct, .enum, .protocol, .interface, .trait]
        var results: [IndexedSymbol] = []
        for kind in typeKinds {
            if let symbols = symbolsByKind[kind] {
                results.append(contentsOf: symbols)
            }
        }
        results.sort { $0.name < $1.name }
        return Array(results.prefix(limit))
    }

    /// List all tests in the codebase
    public func allTests(limit: Int = 200) -> [IndexedSymbol] {
        let tests = symbolsByKind[.test] ?? []
        return Array(tests.prefix(limit))
    }

    // MARK: - Public API: File Search

    /// Search files by name (fuzzy)
    public func findFiles(
        query: String,
        extensionFilter: String? = nil,
        limit: Int = 50
    ) -> [FileNode] {
        let queryLower = query.lowercased()
        var results: [(node: FileNode, score: Int)] = []

        for (_, node) in allFileNodes {
            guard node.kind == .file else { continue }

            if let ext = extensionFilter, node.extension_ != ext {
                continue
            }

            let nameLower = node.name.lowercased()
            let pathLower = node.relativePath.lowercased()

            var score = 0

            // Exact name match
            if nameLower == queryLower {
                score = 1000
            }
            // Name starts with query
            else if nameLower.hasPrefix(queryLower) {
                score = 800
            }
            // Name contains query
            else if nameLower.contains(queryLower) {
                score = 600
            }
            // Path contains query
            else if pathLower.contains(queryLower) {
                score = 400
            }
            // Fuzzy match on name
            else if fuzzyMatch(query: queryLower, target: nameLower) {
                score = 200
            }
            // Fuzzy match on path
            else if fuzzyMatch(query: queryLower, target: pathLower) {
                score = 100
            } else {
                continue
            }

            // Bonus for source files
            if node.isSourceFile { score += 10 }
            // Bonus for shorter paths (less deep)
            score += max(0, 20 - node.depth * 2)

            results.append((node: node, score: score))
        }

        results.sort { $0.score > $1.score }
        return results.prefix(limit).map(\.node)
    }

    /// Glob pattern matching (simplified)
    public func glob(pattern: String, limit: Int = 200) -> [FileNode] {
        let patternLower = pattern.lowercased()
        var results: [FileNode] = []

        for (_, node) in allFileNodes {
            guard node.kind == .file else { continue }
            if matchGlob(pattern: patternLower, path: node.relativePath.lowercased()) {
                results.append(node)
                if results.count >= limit { break }
            }
        }

        results.sort { $0.relativePath < $1.relativePath }
        return results
    }

    // MARK: - Public API: References

    /// Find all references to a symbol in the codebase (grep-based)
    public func findReferences(
        symbolName: String,
        limit: Int = 100
    ) -> [SymbolReference] {
        var references: [SymbolReference] = []

        // First: find definitions
        if let definitions = symbolsByName[symbolName.lowercased()] {
            for def in definitions {
                references.append(
                    SymbolReference(
                        symbolName: symbolName,
                        filePath: def.filePath,
                        line: def.line,
                        contextLine: def.signature,
                        isDefinition: true
                    ))
            }
        }

        // Then: grep through all indexed source files for the symbol name
        let wordPattern = "\\b\(NSRegularExpression.escapedPattern(for: symbolName))\\b"
        guard let regex = try? NSRegularExpression(pattern: wordPattern) else {
            return references
        }

        for (relativePath, indexedFile) in indexedFiles {
            // Skip the definition files we already added
            let definitionLines = Set(
                references.filter { $0.filePath == relativePath && $0.isDefinition }.map(\.line))

            guard let data = FileManager.default.contents(atPath: indexedFile.absolutePath),
                let content = String(data: data, encoding: .utf8)
            else { continue }

            let lines = content.components(separatedBy: "\n")
            for (lineIdx, line) in lines.enumerated() {
                let lineNum = lineIdx + 1
                if definitionLines.contains(lineNum) { continue }

                let range = NSRange(line.startIndex..., in: line)
                if regex.firstMatch(in: line, range: range) != nil {
                    references.append(
                        SymbolReference(
                            symbolName: symbolName,
                            filePath: relativePath,
                            line: lineNum,
                            contextLine: line.trimmingCharacters(in: .whitespaces),
                            isDefinition: false
                        ))
                }

                if references.count >= limit { break }
            }

            if references.count >= limit { break }
        }

        return references
    }

    // MARK: - Public API: File Outline

    /// Returns the outline of a file (hierarchical symbols with line numbers)
    public func fileOutline(relativePath: String) -> String {
        guard let indexed = indexedFiles[relativePath] else {
            return "(file not indexed: \(relativePath))"
        }
        if indexed.symbols.isEmpty {
            return
                "📄 \(relativePath) (\(indexed.language.rawValue), \(indexed.lineCount) lines)\n  (no symbols found)"
        }

        var lines: [String] = []
        lines.append("📄 \(relativePath) (\(indexed.language.rawValue), \(indexed.lineCount) lines)")
        if !indexed.imports.isEmpty {
            lines.append("  Imports: \(indexed.imports.joined(separator: ", "))")
        }
        lines.append("")

        // Group by container
        var topLevel: [IndexedSymbol] = []
        var byContainer: [String: [IndexedSymbol]] = [:]

        for symbol in indexed.symbols {
            if let container = symbol.containerName {
                byContainer[container, default: []].append(symbol)
            } else {
                topLevel.append(symbol)
            }
        }

        for symbol in topLevel {
            let rangeStr =
                symbol.endLine > 0 ? "L\(symbol.line)-\(symbol.endLine)" : "L\(symbol.line)"
            let accessStr =
                symbol.accessLevel == .internal ? "" : "[\(symbol.accessLevel.rawValue)] "
            let staticStr = symbol.isStatic ? "static " : ""
            lines.append(
                "  \(accessStr)\(staticStr)\(symbol.kind.rawValue) \(symbol.name) (\(rangeStr))")

            if !symbol.inherits.isEmpty {
                lines.append("    : \(symbol.inherits.joined(separator: ", "))")
            }
            if let doc = symbol.documentation {
                lines.append("    /// \(doc.prefix(100))")
            }

            // Nested members
            if let members = byContainer[symbol.name] {
                for member in members {
                    let mRange =
                        member.endLine > 0 ? "L\(member.line)-\(member.endLine)" : "L\(member.line)"
                    let mAccess =
                        member.accessLevel == .internal ? "" : "[\(member.accessLevel.rawValue)] "
                    let mStatic = member.isStatic ? "static " : ""
                    lines.append(
                        "    \(mAccess)\(mStatic)\(member.kind.rawValue) \(member.name) (\(mRange))"
                    )
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Public API: Project Structure

    /// Returns the project tree as a string (for LLM context)
    public func projectTree(
        maxDepth: Int = 4,
        maxFiles: Int = 500,
        includeHidden: Bool = false
    ) -> String {
        var result = ""
        for (rootPath, tree) in fileTrees.sorted(by: { $0.key < $1.key }) {
            let rootName = (rootPath as NSString).lastPathComponent
            result += "📁 \(rootName)/\n"
            result += buildTreeString(
                node: tree,
                prefix: "",
                isLast: true,
                currentDepth: 0,
                maxDepth: maxDepth,
                maxFiles: maxFiles,
                includeHidden: includeHidden
            )
            result += "\n"
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Public API: Dependency Graph

    /// Returns the dependencies of a file (imports and files that import it)
    public func fileDependencies(_ relativePath: String) -> (
        imports: [String], importedBy: [String]
    ) {
        let imports = importGraph[relativePath] ?? []
        var importedBy: [String] = []

        // Find all files that import the modules this file defines
        for (file, fileImports) in importGraph {
            if file == relativePath { continue }
            // Check if any import overlaps with what this file provides
            let thisModules = Set(indexedFiles[relativePath]?.imports ?? [])
            let otherImports = Set(fileImports)
            if !thisModules.intersection(otherImports).isEmpty {
                importedBy.append(file)
            }
        }

        return (imports: imports, importedBy: importedBy)
    }

    /// Returns the dependency graph between modules
    public func moduleGraph() -> [DependencyEdge] {
        var edges: [DependencyEdge] = []
        for (file, imports) in importGraph {
            for imp in imports {
                edges.append(
                    DependencyEdge(
                        fromFile: file,
                        toFile: imp,
                        kind: .import
                    ))
            }
        }
        return edges
    }

    // MARK: - Public API: Statistics

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

    // MARK: - Private: File Tree Building

    func buildFileTree(
        at url: URL,
        relativePath: String,
        depth: Int
    ) -> FileNode {
        let fm = FileManager.default
        let name = url.lastPathComponent

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return FileNode(
                name: name,
                kind: .file,
                extension_: url.pathExtension.isEmpty ? nil : url.pathExtension.lowercased(),
                relativePath: relativePath.isEmpty ? name : relativePath,
                absolutePath: url.path,
                depth: depth
            )
        }

        if isDir.boolValue {
            let relPath = relativePath.isEmpty ? name : relativePath

            // Check if excluded
            if Self.defaultExcludedDirs.contains(name) || isExcluded(name, relativePath: relPath) || isGitignored(relPath, isDirectory: true) {
                return FileNode(
                    name: name,
                    kind: .directory,
                    relativePath: relPath,
                    absolutePath: url.path,
                    depth: depth,
                    children: []
                )
            }

            // List children
            guard
                let contents = try? fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [
                        .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
                    ],
                    options: [.skipsHiddenFiles]
                )
            else {
                return FileNode(
                    name: name,
                    kind: .directory,
                    relativePath: relPath,
                    absolutePath: url.path,
                    depth: depth,
                    children: []
                )
            }

            let children =
                contents
                .sorted {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                        == .orderedAscending
                }
                .map { childURL in
                    let childRel =
                        relPath.isEmpty
                        ? childURL.lastPathComponent : "\(relPath)/\(childURL.lastPathComponent)"
                    return buildFileTree(at: childURL, relativePath: childRel, depth: depth + 1)
                }

            return FileNode(
                name: name,
                kind: .directory,
                relativePath: relPath,
                absolutePath: url.path,
                depth: depth,
                children: children
            )
        } else {
            // File
            let ext = url.pathExtension.lowercased()
            var size: UInt64 = 0
            var modDate = Date.distantPast
            if let attrs = try? fm.attributesOfItem(atPath: url.path) {
                size = attrs[.size] as? UInt64 ?? 0
                modDate = attrs[.modificationDate] as? Date ?? .distantPast
            }

            return FileNode(
                name: name,
                kind: .file,
                extension_: ext.isEmpty ? nil : ext,
                relativePath: relativePath.isEmpty ? name : relativePath,
                absolutePath: url.path,
                depth: depth,
                size: size,
                modifiedAt: modDate
            )
        }
    }

    /// Flattens all nodes into the allFileNodes index
    func flattenNodes(_ node: FileNode) {
        if node.kind == .file {
            allFileNodes[node.relativePath] = node
        } else {
            allFileNodes[node.relativePath] = node
            for child in node.children {
                flattenNodes(child)
            }
        }
    }

    // MARK: - Private: Indexing Helpers

    func addIndexedFile(_ indexed: IndexedFile) {
        indexedFiles[indexed.relativePath] = indexed
        contentHashes[indexed.absolutePath] = indexed.contentHash

        for symbol in indexed.symbols {
            let key = symbol.name.lowercased()
            symbolsByName[key, default: []].append(symbol)
            symbolsByFile[indexed.relativePath, default: []].append(symbol)
            symbolsByKind[symbol.kind, default: []].append(symbol)
            totalSymbolsExtracted += 1
        }
    }

    func removeIndexedFile(_ relativePath: String) {
        guard let existing = indexedFiles[relativePath] else { return }

        // Remove symbols
        for symbol in existing.symbols {
            let key = symbol.name.lowercased()
            symbolsByName[key]?.removeAll { $0.id == symbol.id }
            if symbolsByName[key]?.isEmpty == true {
                symbolsByName.removeValue(forKey: key)
            }
            symbolsByKind[symbol.kind]?.removeAll { $0.id == symbol.id }
            if symbolsByKind[symbol.kind]?.isEmpty == true {
                symbolsByKind.removeValue(forKey: symbol.kind)
            }
            totalSymbolsExtracted -= 1
        }
        symbolsByFile.removeValue(forKey: relativePath)
        contentHashes.removeValue(forKey: existing.absolutePath)
        indexedFiles.removeValue(forKey: relativePath)
    }

    func buildImportGraph() {
        importGraph.removeAll()
        reverseImportGraph.removeAll()

        for (relativePath, indexed) in indexedFiles {
            importGraph[relativePath] = indexed.imports
            for imp in indexed.imports {
                reverseImportGraph[imp, default: []].append(relativePath)
            }
        }
    }

    func countDirectories(_ node: FileNode) -> Int {
        if node.kind != .directory { return 0 }
        return 1 + node.children.reduce(0) { $0 + countDirectories($1) }
    }

    func languageBreakdown() -> [FileLanguage: Int] {
        var counts: [FileLanguage: Int] = [:]
        for indexed in indexedFiles.values {
            counts[indexed.language, default: 0] += 1
        }
        return counts
    }

    func isExcluded(_ name: String, relativePath: String = "") -> Bool {
        for pattern in excludedPaths {
            // Exact name match (existing behavior)
            if name == pattern { return true }
            // Path prefix match: "Sources/Generated" matches files under that path
            if !relativePath.isEmpty && !pattern.contains("*") {
                if relativePath == pattern || relativePath.hasPrefix(pattern + "/") { return true }
            }
            // Glob pattern match
            if pattern.contains("*") {
                let pathToCheck = relativePath.isEmpty ? name : relativePath
                if matchGlob(pattern: pattern.lowercased(), path: pathToCheck.lowercased()) { return true }
            }
        }
        return false
    }

    // MARK: - Private: Tree String Builder

    func buildTreeString(
        node: FileNode,
        prefix: String,
        isLast: Bool,
        currentDepth: Int,
        maxDepth: Int,
        maxFiles: Int,
        includeHidden: Bool
    ) -> String {
        guard currentDepth < maxDepth else { return "" }

        var result = ""
        let sortedChildren = node.children.sorted { a, b in
            if a.kind != b.kind { return a.kind == .directory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        let filtered =
            includeHidden ? sortedChildren : sortedChildren.filter { !$0.name.hasPrefix(".") }
        let shown = Array(filtered.prefix(maxFiles))
        let truncated = filtered.count > maxFiles

        for (i, child) in shown.enumerated() {
            let isChildLast = (i == shown.count - 1) && !truncated
            let connector = isChildLast ? "└── " : "├── "
            let childPrefix = isChildLast ? "    " : "│   "

            if child.kind == .directory {
                let fileCount = child.totalFileCount
                result += "\(prefix)\(connector)\(child.name)/ (\(fileCount) files)\n"
                result += buildTreeString(
                    node: child,
                    prefix: prefix + childPrefix,
                    isLast: isChildLast,
                    currentDepth: currentDepth + 1,
                    maxDepth: maxDepth,
                    maxFiles: maxFiles,
                    includeHidden: includeHidden
                )
            } else {
                let sizeStr = ByteCountFormatter.string(
                    fromByteCount: Int64(child.size), countStyle: .file)
                result += "\(prefix)\(connector)\(child.name) (\(sizeStr))\n"
            }
        }

        if truncated {
            result += "\(prefix)└── ... (\(filtered.count - maxFiles) more)\n"
        }

        return result
    }

    // MARK: - Private: Gitignore & File Exclusion

    /// Parse .gitignore from the workspace root
    func loadGitignoreRules(for rootURL: URL) {
        gitignoreRules = []
        let gitignorePath = rootURL.appendingPathComponent(".gitignore").path
        guard let content = try? String(contentsOfFile: gitignorePath, encoding: .utf8) else { return }

        for line in content.components(separatedBy: .newlines) {
            var rule = line.trimmingCharacters(in: .whitespaces)
            if rule.isEmpty || rule.hasPrefix("#") { continue }

            let isNegation = rule.hasPrefix("!")
            if isNegation { rule = String(rule.dropFirst()) }

            let isDirectoryOnly = rule.hasSuffix("/")
            if isDirectoryOnly { rule = String(rule.dropLast()) }

            gitignoreRules.append((pattern: rule, isNegation: isNegation, isDirectoryOnly: isDirectoryOnly))
        }
        Self.logger.debug("loadGitignoreRules: loaded \(self.gitignoreRules.count) rules")
    }

    /// Check if a relative path is gitignored (last matching rule wins, like git)
    func isGitignored(_ relativePath: String, isDirectory: Bool) -> Bool {
        guard respectGitignore, !gitignoreRules.isEmpty, !relativePath.isEmpty else { return false }

        var ignored = false
        for rule in gitignoreRules {
            // Directory-only rules don't apply to files
            if rule.isDirectoryOnly && !isDirectory { continue }

            let matches: Bool
            if rule.pattern.contains("*") || rule.pattern.contains("?") {
                matches = matchGlob(pattern: rule.pattern.lowercased(), path: relativePath.lowercased())
            } else if rule.pattern.contains("/") {
                // Path-based rule: match as prefix
                matches = relativePath == rule.pattern || relativePath.hasPrefix(rule.pattern + "/")
            } else {
                // Name-based rule: match any path component
                let name = (relativePath as NSString).lastPathComponent
                matches = name == rule.pattern || relativePath.hasSuffix("/\(rule.pattern)")
            }

            if matches {
                ignored = !rule.isNegation
            }
        }
        return ignored
    }

    /// Check if a file should be excluded by file patterns
    func isFileExcluded(_ relativePath: String) -> Bool {
        guard !excludedFilePatterns.isEmpty else { return false }
        for pattern in excludedFilePatterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if matchGlob(pattern: trimmed.lowercased(), path: relativePath.lowercased()) {
                return true
            }
        }
        return false
    }

    // MARK: - Private: Pattern Matching

    /// Simple fuzzy subsequence match
    func fuzzyMatch(query: String, target: String) -> Bool {
        var queryIdx = query.startIndex
        var targetIdx = target.startIndex

        while queryIdx < query.endIndex && targetIdx < target.endIndex {
            if query[queryIdx] == target[targetIdx] {
                queryIdx = query.index(after: queryIdx)
            }
            targetIdx = target.index(after: targetIdx)
        }

        return queryIdx == query.endIndex
    }

    /// Simplified glob matching (supports * and **)
    func matchGlob(pattern: String, path: String) -> Bool {
        // Simple cases
        if pattern == "*" { return true }
        if pattern == path { return true }

        // Convert glob to a simple check
        if pattern.hasPrefix("**/*.") || pattern.hasPrefix("*.") {
            let ext = String(pattern.split(separator: ".").last ?? "")
            return path.hasSuffix(".\(ext)")
        }

        if pattern.hasPrefix("**/") {
            let suffix = String(pattern.dropFirst(3))
            return path.hasSuffix(suffix) || path.contains("/\(suffix)")
        }

        if pattern.hasSuffix("/**") {
            let prefix = String(pattern.dropLast(3))
            return path.hasPrefix(prefix)
        }

        if pattern.contains("*") {
            let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(
                String.init)
            var searchFrom = path.startIndex
            for part in parts {
                if part.isEmpty { continue }
                guard let range = path.range(of: part, range: searchFrom..<path.endIndex) else {
                    return false
                }
                searchFrom = range.upperBound
            }
            return true
        }

        return path.contains(pattern)
    }
}
