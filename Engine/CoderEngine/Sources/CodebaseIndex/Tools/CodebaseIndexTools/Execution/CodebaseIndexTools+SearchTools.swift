import Foundation

// MARK: - Codebase search operations

extension CodebaseIndexTools {
    func executeCodebaseSearch(args: [String: String]) async -> ToolOutput {
        let query = args["query"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            return ToolOutput(
                ok: false, title: "codebase_search", output: "Missing 'query' argument")
        }

        let kindStr = args["kind"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let symbolKinds: [SymbolKind]? = {
            guard let k = kindStr, k != "all", !k.isEmpty else { return nil }
            switch k {
            case "class": return [.class]
            case "struct": return [.struct]
            case "enum": return [.enum]
            case "protocol": return [.protocol]
            case "function", "func": return [.function, .method]
            case "method": return [.method]
            case "property", "var", "let": return [.property, .constant, .variable]
            case "test": return [.test]
            case "type": return [.class, .struct, .enum, .protocol, .interface, .trait]
            case "interface": return [.interface]
            case "trait": return [.trait]
            case "module": return [.module]
            default: return nil
            }
        }()

        let filePattern = args["filePattern"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = await index.semanticGrep(
            query: query,
            filePattern: filePattern,
            symbolKinds: symbolKinds,
            limit: 50
        )

        if results.isEmpty {
            // Fallback to fuzzy symbol search
            let fuzzyResults = await index.findSymbols(
                query: query,
                kind: symbolKinds?.first,
                fileFilter: filePattern,
                limit: 50
            )
            if fuzzyResults.isEmpty {
                return ToolOutput(
                    ok: true,
                    title: "codebase_search: \(query)",
                    output: "No symbols found matching '\(query)'",
                    detail: "0 results"
                )
            }
            return formatSymbolResults(fuzzyResults, title: "codebase_search: \(query)")
        }

        return formatSymbolResults(results, title: "codebase_search: \(query)")
    }

    func executeFindSymbol(args: [String: String]) async -> ToolOutput {
        let query = args["query"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            return ToolOutput(ok: false, title: "find_symbol", output: "Missing 'query' argument")
        }

        let kindStr = args["kind"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let kind: SymbolKind? = {
            guard let k = kindStr, !k.isEmpty else { return nil }
            switch k {
            case "class": return .class
            case "struct": return .struct
            case "enum": return .enum
            case "protocol": return .protocol
            case "function", "func": return .function
            case "method": return .method
            case "property": return .property
            case "test": return .test
            case "interface": return .interface
            case "trait": return .trait
            default: return nil
            }
        }()

        // Try exact match first
        var results = await index.findExactSymbol(name: query, kind: kind)
        if results.isEmpty {
            // Fall back to fuzzy search
            results = await index.findSymbols(query: query, kind: kind, limit: 20)
        }

        if results.isEmpty {
            return ToolOutput(
                ok: true,
                title: "find_symbol: \(query)",
                output: "Symbol '\(query)' not found in the codebase",
                detail: "0 results"
            )
        }

        var lines: [String] = []
        lines.append("Found \(results.count) definition(s) for '\(query)':\n")
        for symbol in results {
            lines.append(symbol.detailedDescription)
            lines.append("")
        }

        return ToolOutput(
            ok: true,
            title: "find_symbol: \(query)",
            output: lines.joined(separator: "\n"),
            detail: "\(results.count) definition(s)"
        )
    }

    func executeListSymbols(args: [String: String]) async -> ToolOutput {
        let path = args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else {
            return ToolOutput(ok: false, title: "list_symbols", output: "Missing 'path' argument")
        }

        let symbols = await index.symbolsInFile(path)
        if symbols.isEmpty {
            // Maybe the path is partial – try to find matching files
            let candidates = await index.findFiles(query: path, limit: 5)
            if let best = candidates.first {
                let bestSymbols = await index.symbolsInFile(best.relativePath)
                if !bestSymbols.isEmpty {
                    return formatFileSymbols(bestSymbols, filePath: best.relativePath)
                }
            }
            return ToolOutput(
                ok: true,
                title: "list_symbols: \(path)",
                output: "No symbols found in '\(path)'. File may not be indexed.",
                detail: "0 symbols"
            )
        }

        return formatFileSymbols(symbols, filePath: path)
    }

    func executeFindReferences(args: [String: String]) async -> ToolOutput {
        let query = args["query"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            return ToolOutput(
                ok: false, title: "find_references", output: "Missing 'query' argument")
        }

        let references = await index.findReferences(symbolName: query, limit: 100)
        if references.isEmpty {
            return ToolOutput(
                ok: true,
                title: "find_references: \(query)",
                output: "No references found for '\(query)'",
                detail: "0 references"
            )
        }

        let definitions = references.filter(\.isDefinition)
        let usages = references.filter { !$0.isDefinition }
        var lines: [String] = []
        lines.append("Found \(references.count) reference(s) for '\(query)':")
        lines.append("  \(definitions.count) definition(s), \(usages.count) usage(s)\n")

        if !definitions.isEmpty {
            lines.append("📍 Definitions:")
            for ref in definitions {
                lines.append("  \(ref.filePath):\(ref.line) — \(ref.contextLine)")
            }
            lines.append("")
        }

        if !usages.isEmpty {
            lines.append("🔗 Usages:")
            for ref in usages.prefix(80) {
                lines.append("  \(ref.filePath):\(ref.line) — \(ref.contextLine)")
            }
            if usages.count > 80 {
                lines.append("  ... and \(usages.count - 80) more")
            }
        }

        return ToolOutput(
            ok: true,
            title: "find_references: \(query)",
            output: lines.joined(separator: "\n"),
            detail: "\(references.count) references (\(definitions.count) defs, \(usages.count) uses)"
        )
    }

    func executeProjectStructure(args: [String: String]) async -> ToolOutput {
        let maxDepthStr = args["maxDepth"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "3"
        let maxDepth = Int(maxDepthStr) ?? 3

        let tree = await index.projectTree(
            maxDepth: min(maxDepth, 6),
            maxFiles: 300,
            includeHidden: false
        )

        if tree.isEmpty {
            return ToolOutput(
                ok: true,
                title: "project_structure",
                output: "(empty workspace — no files found)",
                detail: "0 files"
            )
        }

        let statusInfo = await index.status()
        var output = "Project Structure (depth: \(maxDepth))\n"
        output +=
            "Files: \(statusInfo.totalFiles), Source: \(statusInfo.totalSourceFiles), Symbols: \(statusInfo.totalSymbols)\n\n"
        output += tree

        return ToolOutput(
            ok: true,
            title: "project_structure",
            output: String(output.prefix(8000)),
            detail: "\(statusInfo.totalFiles) files"
        )
    }

    func executeFileOutline(args: [String: String]) async -> ToolOutput {
        let path = args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else {
            return ToolOutput(ok: false, title: "file_outline", output: "Missing 'path' argument")
        }

        // Try exact path first
        var outline = await index.fileOutline(relativePath: path)
        if outline.contains("file not indexed") {
            // Try fuzzy file search
            let candidates = await index.findFiles(query: path, limit: 3)
            if let best = candidates.first {
                outline = await index.fileOutline(relativePath: best.relativePath)
            }
        }

        return ToolOutput(
            ok: true,
            title: "file_outline: \(path)",
            output: String(outline.prefix(6000)),
            detail: "outline"
        )
    }

    func executeFindFiles(args: [String: String]) async -> ToolOutput {
        let query = args["query"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            return ToolOutput(ok: false, title: "find_files", output: "Missing 'query' argument")
        }

        let ext = args["extension"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filePattern = normalizedFilePattern(from: args["filePattern"] ?? args["path"])

        let candidateResults = await index.findFiles(query: query, extensionFilter: ext, limit: 200)
        let scopedResults = await applyFilePattern(candidateResults, filePattern: filePattern)
        if scopedResults.isEmpty {
            // Try glob
            let globResults = await index.glob(pattern: query, limit: 200)
            let scopedGlobResults = await applyFilePattern(globResults, filePattern: filePattern)
            if !scopedGlobResults.isEmpty {
                return formatFileResults(Array(scopedGlobResults.prefix(50)), title: "find_files: \(query)")
            }
            let scopeDetail = filePattern.map { " in '\($0)'" } ?? ""
            return ToolOutput(
                ok: true,
                title: "find_files: \(query)",
                output: "No files found matching '\(query)'\(scopeDetail)",
                detail: "0 results"
            )
        }

        return formatFileResults(Array(scopedResults.prefix(50)), title: "find_files: \(query)")
    }
}
