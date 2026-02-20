import Foundation

// MARK: - CodebaseIndex

/// Actor principale che costruisce e mantiene l'indice del codebase.
/// Scansiona il workspace, estrae simboli da ogni file sorgente,
/// costruisce l'albero dei file e offre API di query veloci.
public actor CodebaseIndex {

    // MARK: - State

    /// Albero dei file per ogni root del workspace
    private var fileTrees: [String: FileNode] = [:]  // rootPath -> FileNode tree

    /// File indicizzati (relativePath -> IndexedFile)
    private var indexedFiles: [String: IndexedFile] = [:]

    /// Lookup simboli per nome (lowercase name -> [IndexedSymbol])
    private var symbolsByName: [String: [IndexedSymbol]] = [:]

    /// Lookup simboli per file (relativePath -> [IndexedSymbol])
    private var symbolsByFile: [String: [IndexedSymbol]] = [:]

    /// Lookup simboli per kind
    private var symbolsByKind: [SymbolKind: [IndexedSymbol]] = [:]

    /// Tutti i nodi file (relativePath -> FileNode)
    private var allFileNodes: [String: FileNode] = [:]

    /// Import graph: file -> [imported modules]
    private var importGraph: [String: [String]] = [:]

    /// Reverse import graph: module -> [files that import it]
    private var reverseImportGraph: [String: [String]] = [:]

    /// Content hashes per invalidazione cache (absolutePath -> hash)
    private var contentHashes: [String: UInt64] = [:]

    /// Timestamp dell'ultima indicizzazione completa
    private var lastFullIndexAt: Date?

    /// Workspace paths attualmente indicizzati
    private var currentWorkspacePaths: [URL] = []

    /// Excluded path patterns
    private var excludedPaths: [String] = []

    /// Status dell'indice
    private var _status: IndexStatus = .idle

    /// Contatori
    private var totalFilesScanned: Int = 0
    private var totalSymbolsExtracted: Int = 0
    private var indexDurationMs: Int = 0

    // MARK: - Configuration

    /// Directory escluse di default
    private static let defaultExcludedDirs: Set<String> = [
        "node_modules", ".git", ".svn", ".hg",
        ".build", "build", "Build", "DerivedData",
        "dist", "out", ".output", ".next", ".nuxt",
        ".cache", ".swiftpm", ".gradle",
        "__pycache__", ".pytest_cache", ".mypy_cache",
        "venv", ".venv", "env", ".env",
        "Pods", "Carthage",
        ".idea", ".vscode", ".vs",
        "vendor", "target",
        "coverage", ".nyc_output",
        ".terraform",
    ]

    /// Estensioni file sorgente indicizzabili
    private static let indexableExtensions: Set<String> = [
        "swift", "m", "mm", "c", "cpp", "cc", "cxx", "h", "hpp", "hxx",
        "py", "pyw", "pyi",
        "js", "mjs", "cjs", "jsx",
        "ts", "mts", "cts", "tsx",
        "go",
        "rs",
        "java",
        "kt", "kts",
        "rb", "rake",
        "php",
        "cs",
        "html", "htm",
        "css", "scss", "sass", "less",
        "json", "jsonc", "json5",
        "yml", "yaml",
        "toml",
        "xml", "plist", "xib", "storyboard",
        "md", "markdown", "rst",
        "sh", "bash", "zsh", "fish",
        "sql",
        "graphql", "gql",
        "proto",
        "dart",
        "ex", "exs",
        "lua",
        "r", "R",
        "scala", "sc",
        "hs",
        "zig",
    ]

    /// Dimensione massima file da indicizzare (1 MB)
    private static let maxFileSize: UInt64 = 1_048_576

    /// Massimo numero di file indicizzabili
    private static let maxFiles: Int = 50_000

    // MARK: - Init

    public init() {}

    // MARK: - Public API: Indexing

    /// Indicizza il workspace completo (full scan)
    public func indexWorkspace(
        paths: [URL],
        excludedPaths: [String] = []
    ) async -> IndexResult {
        let startTime = Date()
        _status = .indexing

        self.currentWorkspacePaths = paths
        self.excludedPaths = excludedPaths

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
        }
        let filesToIndex = Array(sourceFiles.prefix(Self.maxFiles))

        for node in filesToIndex {
            if let indexed = SymbolExtractor.indexFile(
                absolutePath: node.absolutePath,
                relativePath: node.relativePath,
                language: node.language
            ) {
                addIndexedFile(indexed)
                totalFilesScanned += 1
            }
        }

        // 3. Build import graph
        buildImportGraph()

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        indexDurationMs = durationMs
        lastFullIndexAt = Date()
        _status = .ready

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

    /// Indicizzazione incrementale: ri-indicizza solo i file modificati
    public func incrementalUpdate() async -> IndexResult {
        let startTime = Date()
        _status = .indexing

        var updatedCount = 0
        var newSymbols = 0

        for (relativePath, node) in allFileNodes {
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
                newSymbols += indexed.symbols.count
            }
        }

        // Check for new files
        for rootURL in currentWorkspacePaths {
            let tree = buildFileTree(at: rootURL, relativePath: "", depth: 0)
            fileTrees[rootURL.path] = tree
            flattenNodes(tree)
        }

        // Re-build import graph
        buildImportGraph()

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        indexDurationMs = durationMs
        _status = .ready

        return IndexResult(
            totalFiles: allFileNodes.count,
            totalSourceFiles: indexedFiles.count,
            totalSymbols: totalSymbolsExtracted,
            totalDirectories: fileTrees.values.reduce(0) { acc, tree in
                acc + countDirectories(tree)
            },
            durationMs: durationMs,
            languages: languageBreakdown(),
            updatedFiles: updatedCount
        )
    }

    /// Indicizza un singolo file (per aggiornamento in tempo reale)
    public func indexSingleFile(absolutePath: String, relativePath: String) {
        // Remove old entry
        removeIndexedFile(relativePath)

        // Re-index
        if let indexed = SymbolExtractor.indexFile(
            absolutePath: absolutePath,
            relativePath: relativePath
        ) {
            addIndexedFile(indexed)
        }
    }

    // MARK: - Public API: Symbol Search

    /// Cerca simboli per nome (fuzzy match)
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

    /// Cerca un simbolo per nome esatto e tipo
    public func findExactSymbol(name: String, kind: SymbolKind? = nil) -> [IndexedSymbol] {
        let key = name.lowercased()
        guard let candidates = symbolsByName[key] else { return [] }
        if let kind = kind {
            return candidates.filter { $0.kind == kind }
        }
        return candidates
    }

    /// Elenca tutti i simboli in un file
    public func symbolsInFile(_ relativePath: String) -> [IndexedSymbol] {
        return symbolsByFile[relativePath] ?? []
    }

    /// Elenca tutti i tipi (class, struct, enum, protocol, interface, trait) nel codebase
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

    /// Elenca tutti i test nel codebase
    public func allTests(limit: Int = 200) -> [IndexedSymbol] {
        let tests = symbolsByKind[.test] ?? []
        return Array(tests.prefix(limit))
    }

    // MARK: - Public API: File Search

    /// Cerca file per nome (fuzzy)
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

    /// Glob pattern matching (semplificato)
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

    /// Trova tutti i riferimenti a un simbolo nel codebase (grep-based)
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

    /// Restituisce l'outline di un file (simboli gerarchici con numeri di riga)
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

    /// Restituisce l'albero del progetto come stringa (per contesto LLM)
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

    /// Restituisce le dipendenze di un file (imports e file che lo importano)
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

    /// Restituisce il grafo delle dipendenze tra moduli
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

    /// Statistiche complete del codebase
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

    /// Stato corrente dell'indice
    public func status() -> IndexStatusInfo {
        return IndexStatusInfo(
            status: _status,
            totalFiles: allFileNodes.count,
            totalSourceFiles: indexedFiles.count,
            totalSymbols: totalSymbolsExtracted,
            lastIndexedAt: lastFullIndexAt,
            indexDurationMs: indexDurationMs,
            workspacePaths: currentWorkspacePaths.map(\.path)
        )
    }

    /// Sommario dell'indice in formato testo (per contesto LLM)
    public func summaryText() -> String {
        let info = IndexStatusInfo(
            status: _status,
            totalFiles: allFileNodes.count,
            totalSourceFiles: indexedFiles.count,
            totalSymbols: totalSymbolsExtracted,
            lastIndexedAt: lastFullIndexAt,
            indexDurationMs: indexDurationMs,
            workspacePaths: currentWorkspacePaths.map(\.path)
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

    /// Restituisce la lista di tutti i file indicizzati
    public func allIndexedFilePaths() -> [String] {
        return Array(indexedFiles.keys).sorted()
    }

    /// Restituisce un IndexedFile specifico
    public func getIndexedFile(_ relativePath: String) -> IndexedFile? {
        return indexedFiles[relativePath]
    }

    /// Restituisce un FileNode specifico
    public func getFileNode(_ relativePath: String) -> FileNode? {
        return allFileNodes[relativePath]
    }

    /// Ricerca avanzata: grep semantico usando l'indice
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

    private func buildFileTree(
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
            if Self.defaultExcludedDirs.contains(name) || isExcluded(name) {
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

    /// Appiattisce tutti i nodi nell'indice allFileNodes
    private func flattenNodes(_ node: FileNode) {
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

    private func addIndexedFile(_ indexed: IndexedFile) {
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

    private func removeIndexedFile(_ relativePath: String) {
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

    private func buildImportGraph() {
        importGraph.removeAll()
        reverseImportGraph.removeAll()

        for (relativePath, indexed) in indexedFiles {
            importGraph[relativePath] = indexed.imports
            for imp in indexed.imports {
                reverseImportGraph[imp, default: []].append(relativePath)
            }
        }
    }

    private func countDirectories(_ node: FileNode) -> Int {
        if node.kind != .directory { return 0 }
        return 1 + node.children.reduce(0) { $0 + countDirectories($1) }
    }

    private func languageBreakdown() -> [FileLanguage: Int] {
        var counts: [FileLanguage: Int] = [:]
        for indexed in indexedFiles.values {
            counts[indexed.language, default: 0] += 1
        }
        return counts
    }

    private func isExcluded(_ name: String) -> Bool {
        excludedPaths.contains(name)
    }

    // MARK: - Private: Tree String Builder

    private func buildTreeString(
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

    // MARK: - Private: Pattern Matching

    /// Simple fuzzy subsequence match
    private func fuzzyMatch(query: String, target: String) -> Bool {
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
    private func matchGlob(pattern: String, path: String) -> Bool {
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

// MARK: - Result Types

/// Risultato dell'indicizzazione
public struct IndexResult: Sendable {
    public let totalFiles: Int
    public let totalSourceFiles: Int
    public let totalSymbols: Int
    public let totalDirectories: Int
    public let durationMs: Int
    public let languages: [FileLanguage: Int]
    public let updatedFiles: Int

    public init(
        totalFiles: Int,
        totalSourceFiles: Int,
        totalSymbols: Int,
        totalDirectories: Int,
        durationMs: Int,
        languages: [FileLanguage: Int],
        updatedFiles: Int = 0
    ) {
        self.totalFiles = totalFiles
        self.totalSourceFiles = totalSourceFiles
        self.totalSymbols = totalSymbols
        self.totalDirectories = totalDirectories
        self.durationMs = durationMs
        self.languages = languages
        self.updatedFiles = updatedFiles
    }

    /// Sommario testuale
    public var summary: String {
        var lines: [String] = []
        lines.append("✅ Index complete in \(durationMs)ms")
        lines.append("  Files: \(totalFiles) total, \(totalSourceFiles) source")
        lines.append("  Directories: \(totalDirectories)")
        lines.append("  Symbols: \(totalSymbols)")
        if updatedFiles > 0 {
            lines.append("  Updated: \(updatedFiles) files")
        }
        if !languages.isEmpty {
            let sorted = languages.sorted { $0.value > $1.value }
            lines.append(
                "  Languages: "
                    + sorted.prefix(8).map { "\($0.key.rawValue)(\($0.value))" }.joined(
                        separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}

/// Stato dell'indice
public enum IndexStatus: String, Sendable {
    case idle
    case indexing
    case ready
    case error
}

/// Informazioni sullo stato dell'indice
public struct IndexStatusInfo: Sendable {
    public let status: IndexStatus
    public let totalFiles: Int
    public let totalSourceFiles: Int
    public let totalSymbols: Int
    public let lastIndexedAt: Date?
    public let indexDurationMs: Int
    public let workspacePaths: [String]
}
