import Foundation

extension CodebaseIndex {
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

}
