import Foundation

extension CodebaseIndex {
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
}
