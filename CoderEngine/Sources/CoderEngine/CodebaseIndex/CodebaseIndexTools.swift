import Foundation

// MARK: - CodebaseIndexTools

/// Integrates CodebaseIndex with MCP/UnifiedToolRuntime.
/// Exposes codebase index operations as LLM-invokable tools.
public actor CodebaseIndexTools {

    private let index: CodebaseIndex

    public init(index: CodebaseIndex) {
        self.index = index
    }

    // MARK: - Tool Definitions (for LLM prompt injection)

    /// Returns the description of index tools for the LLM prompt.
    public static var toolDefinitionsPrompt: String {
        """
        ## Codebase Index Tools

        You have access to codebase-index powered tools. Use CoderIDE markers to invoke them:

        ### codebase_search
        Search symbols, types, and functions using the structured index.
        Much faster and more precise than grep for finding definitions.
        [CODERIDE:tool_call|id=<uuid>|name=codebase_search|query=<search_query>|kind=<class|struct|enum|protocol|function|method|property|test|all>|filePattern=<optional_glob>]

        ### find_symbol
        Find exact symbol definitions (class, function, struct, protocol).
        [CODERIDE:tool_call|id=<uuid>|name=find_symbol|query=<symbol_name>|kind=<optional_kind>]

        ### list_symbols
        List all symbols in a specific file (file outline).
        [CODERIDE:tool_call|id=<uuid>|name=list_symbols|path=<relative_file_path>]

        ### find_references
        Find all references to a symbol in the codebase (definitions + usages).
        [CODERIDE:tool_call|id=<uuid>|name=find_references|query=<symbol_name>]

        ### project_structure
        Show the project tree structure.
        [CODERIDE:tool_call|id=<uuid>|name=project_structure|maxDepth=<2|3|4>]

        ### file_outline
        Get a structured file outline (symbols with line numbers).
        [CODERIDE:tool_call|id=<uuid>|name=file_outline|path=<relative_file_path>]

        ### find_files
        Find files by name with fuzzy matching.
        [CODERIDE:tool_call|id=<uuid>|name=find_files|query=<filename_query>|extension=<optional_ext>]

        ### codebase_stats
        Codebase statistics: files, languages, sizes, symbols.
        [CODERIDE:tool_call|id=<uuid>|name=codebase_stats]

        ### dependency_graph
        Show a file's dependencies (imports) and reverse imports.
        [CODERIDE:tool_call|id=<uuid>|name=dependency_graph|path=<relative_file_path>]

        ### list_types
        List all types (class, struct, enum, protocol) in the codebase.
        [CODERIDE:tool_call|id=<uuid>|name=list_types]

        ### list_tests
        List all tests in the codebase.
        [CODERIDE:tool_call|id=<uuid>|name=list_tests]

        ### index_status
        Show codebase index status.
        [CODERIDE:tool_call|id=<uuid>|name=index_status]

        ### reindex
        Force workspace reindexing (incremental if already indexed).
        [CODERIDE:tool_call|id=<uuid>|name=reindex]
        """
    }

    /// Tool names handled by the index.
    public static let handledToolNames: Set<String> = [
        "codebase_search",
        "find_symbol",
        "list_symbols",
        "find_references",
        "project_structure",
        "file_outline",
        "find_files",
        "codebase_stats",
        "dependency_graph",
        "list_types",
        "list_tests",
        "index_status",
        "reindex",
    ]

    /// Returns whether a tool name is handled by the index.
    public static func handles(toolName: String) -> Bool {
        handledToolNames.contains(toolName)
    }

    // MARK: - Tool Execution

    /// Executes an index tool and returns StreamEvent values.
    public func execute(
        toolName: String,
        args: [String: String],
        callId: String,
        workspacePaths: [URL],
        excludedPaths: [String] = []
    ) async -> [StreamEvent] {
        let startTime = Date()

        // Ensure index is built
        let status = await index.status()
        if shouldPerformFullReindex(statusInfo: status, workspacePaths: workspacePaths) {
            let _ = await index.indexWorkspace(paths: workspacePaths, excludedPaths: excludedPaths)
        }

        let result: ToolOutput
        switch toolName {
        case "codebase_search":
            result = await executeCodebaseSearch(args: args)
        case "find_symbol":
            result = await executeFindSymbol(args: args)
        case "list_symbols":
            result = await executeListSymbols(args: args)
        case "find_references":
            result = await executeFindReferences(args: args)
        case "project_structure":
            result = await executeProjectStructure(args: args)
        case "file_outline":
            result = await executeFileOutline(args: args)
        case "find_files":
            result = await executeFindFiles(args: args)
        case "codebase_stats":
            result = await executeCodebaseStats()
        case "dependency_graph":
            result = await executeDependencyGraph(args: args)
        case "list_types":
            result = await executeListTypes()
        case "list_tests":
            result = await executeListTests()
        case "index_status":
            result = await executeIndexStatus()
        case "reindex":
            result = await executeReindex(
                workspacePaths: workspacePaths, excludedPaths: excludedPaths)
        default:
            result = ToolOutput(
                ok: false, title: "Unknown tool",
                output: "Tool '\(toolName)' not found in codebase index")
        }

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        // Build started event
        var startedPayload: [String: String] = [
            "tool_call_id": callId,
            "tool": toolName,
            "status": "started",
            "title": result.title,
        ]
        if let query = args["query"], !query.isEmpty {
            startedPayload["query"] = query
        }

        // Build completed event
        var completedPayload: [String: String] = [
            "tool_call_id": callId,
            "tool": toolName,
            "status": result.ok ? "completed" : "failed",
            "title": result.title,
            "output": result.output,
            "duration_ms": "\(durationMs)",
        ]
        if let detail = result.detail {
            completedPayload["detail"] = detail
        }

        let eventType = result.ok ? "read_batch_completed" : "tool_execution_error"

        return [
            .raw(type: "mcp_tool_call", payload: startedPayload),
            .raw(type: eventType, payload: completedPayload),
        ]
    }

    // MARK: - Individual Tool Implementations

    private func executeCodebaseSearch(args: [String: String]) async -> ToolOutput {
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

    private func executeFindSymbol(args: [String: String]) async -> ToolOutput {
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

    private func executeListSymbols(args: [String: String]) async -> ToolOutput {
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

    private func executeFindReferences(args: [String: String]) async -> ToolOutput {
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
            detail:
                "\(references.count) references (\(definitions.count) defs, \(usages.count) uses)"
        )
    }

    private func executeProjectStructure(args: [String: String]) async -> ToolOutput {
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

    private func executeFileOutline(args: [String: String]) async -> ToolOutput {
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

    private func executeFindFiles(args: [String: String]) async -> ToolOutput {
        let query = args["query"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            return ToolOutput(ok: false, title: "find_files", output: "Missing 'query' argument")
        }

        let ext = args["extension"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        let results = await index.findFiles(query: query, extensionFilter: ext, limit: 50)

        if results.isEmpty {
            // Try glob
            let globResults = await index.glob(pattern: query, limit: 50)
            if !globResults.isEmpty {
                return formatFileResults(globResults, title: "find_files: \(query)")
            }
            return ToolOutput(
                ok: true,
                title: "find_files: \(query)",
                output: "No files found matching '\(query)'",
                detail: "0 results"
            )
        }

        return formatFileResults(results, title: "find_files: \(query)")
    }

    private func executeCodebaseStats() async -> ToolOutput {
        let stats = await index.stats()
        let statusInfo = await index.status()

        var lines: [String] = []
        lines.append(stats.summary)
        lines.append("")
        lines.append("Symbols: \(statusInfo.totalSymbols)")
        lines.append("Indexed source files: \(statusInfo.totalSourceFiles)")
        if let date = statusInfo.lastIndexedAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            lines.append(
                "Last indexed: \(formatter.string(from: date)) (\(statusInfo.indexDurationMs)ms)")
        }

        return ToolOutput(
            ok: true,
            title: "codebase_stats",
            output: lines.joined(separator: "\n"),
            detail: "\(stats.totalFiles) files, \(statusInfo.totalSymbols) symbols"
        )
    }

    private func executeDependencyGraph(args: [String: String]) async -> ToolOutput {
        let path = args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else {
            return ToolOutput(
                ok: false, title: "dependency_graph", output: "Missing 'path' argument")
        }

        // Try exact path, then fuzzy
        var resolvedPath = path
        let fileNode = await index.getFileNode(path)
        if fileNode == nil {
            let candidates = await index.findFiles(query: path, limit: 1)
            if let best = candidates.first {
                resolvedPath = best.relativePath
            }
        }

        let deps = await index.fileDependencies(resolvedPath)

        var lines: [String] = []
        lines.append("📄 \(resolvedPath)\n")

        if deps.imports.isEmpty {
            lines.append("Imports: (none)")
        } else {
            lines.append("Imports (\(deps.imports.count)):")
            for imp in deps.imports {
                lines.append("  → \(imp)")
            }
        }

        lines.append("")

        if deps.importedBy.isEmpty {
            lines.append("Imported by: (none)")
        } else {
            lines.append("Imported by (\(deps.importedBy.count)):")
            for file in deps.importedBy.prefix(50) {
                lines.append("  ← \(file)")
            }
            if deps.importedBy.count > 50 {
                lines.append("  ... and \(deps.importedBy.count - 50) more")
            }
        }

        return ToolOutput(
            ok: true,
            title: "dependency_graph: \(resolvedPath)",
            output: lines.joined(separator: "\n"),
            detail: "\(deps.imports.count) imports, \(deps.importedBy.count) dependents"
        )
    }

    private func executeListTypes() async -> ToolOutput {
        let types = await index.allTypes(limit: 200)

        if types.isEmpty {
            return ToolOutput(
                ok: true,
                title: "list_types",
                output: "No types found in the codebase",
                detail: "0 types"
            )
        }

        var lines: [String] = []
        lines.append("Found \(types.count) type(s) in the codebase:\n")

        // Group by kind
        var byKind: [SymbolKind: [IndexedSymbol]] = [:]
        for t in types {
            byKind[t.kind, default: []].append(t)
        }

        let kindOrder: [SymbolKind] = [.class, .struct, .enum, .protocol, .interface, .trait]
        for kind in kindOrder {
            guard let symbols = byKind[kind], !symbols.isEmpty else { continue }
            lines.append("\(kind.rawValue.uppercased()) (\(symbols.count)):")
            for s in symbols {
                let access = s.accessLevel == .internal ? "" : "[\(s.accessLevel.rawValue)] "
                let inheritsStr =
                    s.inherits.isEmpty ? "" : " : \(s.inherits.joined(separator: ", "))"
                lines.append("  \(access)\(s.name)\(inheritsStr)  — \(s.filePath):\(s.line)")
            }
            lines.append("")
        }

        return ToolOutput(
            ok: true,
            title: "list_types",
            output: String(lines.joined(separator: "\n").prefix(8000)),
            detail: "\(types.count) types"
        )
    }

    private func executeListTests() async -> ToolOutput {
        let tests = await index.allTests(limit: 200)

        if tests.isEmpty {
            return ToolOutput(
                ok: true,
                title: "list_tests",
                output: "No tests found in the codebase",
                detail: "0 tests"
            )
        }

        var lines: [String] = []
        lines.append("Found \(tests.count) test(s) in the codebase:\n")

        // Group by container
        var byContainer: [String: [IndexedSymbol]] = [:]
        var standalone: [IndexedSymbol] = []
        for t in tests {
            if let container = t.containerName {
                byContainer[container, default: []].append(t)
            } else {
                standalone.append(t)
            }
        }

        for (container, tests) in byContainer.sorted(by: { $0.key < $1.key }) {
            lines.append("\(container) (\(tests.count) tests):")
            for t in tests {
                lines.append("  \(t.name)  — \(t.filePath):\(t.line)")
            }
            lines.append("")
        }

        if !standalone.isEmpty {
            lines.append("Standalone tests (\(standalone.count)):")
            for t in standalone {
                lines.append("  \(t.name)  — \(t.filePath):\(t.line)")
            }
        }

        return ToolOutput(
            ok: true,
            title: "list_tests",
            output: String(lines.joined(separator: "\n").prefix(8000)),
            detail: "\(tests.count) tests"
        )
    }

    private func executeIndexStatus() async -> ToolOutput {
        let summary = await index.summaryText()
        let info = await index.status()

        return ToolOutput(
            ok: true,
            title: "index_status",
            output: summary,
            detail: "\(info.status.rawValue) — \(info.totalSymbols) symbols"
        )
    }

    private func executeReindex(
        workspacePaths: [URL],
        excludedPaths: [String]
    ) async -> ToolOutput {
        let info = await index.status()

        let result: IndexResult
        if info.status == .ready,
           !shouldPerformFullReindex(statusInfo: info, workspacePaths: workspacePaths) {
            result = await index.incrementalUpdate()
        } else {
            result = await index.indexWorkspace(paths: workspacePaths, excludedPaths: excludedPaths)
        }

        return ToolOutput(
            ok: true,
            title: "reindex",
            output: result.summary,
            detail: "\(result.totalSymbols) symbols in \(result.durationMs)ms"
        )
    }

    private func shouldPerformFullReindex(
        statusInfo: IndexStatusInfo,
        workspacePaths: [URL]
    ) -> Bool {
        if statusInfo.status == .idle || statusInfo.status == .error {
            return true
        }
        let requested = normalizeWorkspacePaths(workspacePaths)
        guard !requested.isEmpty else { return false }
        let indexed = normalizeWorkspacePaths(statusInfo.workspacePaths)
        return requested != indexed
    }

    private func normalizeWorkspacePaths(_ paths: [URL]) -> [String] {
        let values = paths.map { $0.standardizedFileURL.path }
        return normalizeWorkspacePaths(values)
    }

    private func normalizeWorkspacePaths(_ paths: [String]) -> [String] {
        var normalized = Set<String>()
        for rawPath in paths {
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let value = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            normalized.insert(value)
        }
        return normalized.sorted()
    }

    // MARK: - Formatting Helpers

    private func formatSymbolResults(_ symbols: [IndexedSymbol], title: String) -> ToolOutput {
        var lines: [String] = []
        lines.append("Found \(symbols.count) result(s):\n")

        for symbol in symbols {
            lines.append(symbol.compactDescription)
        }

        return ToolOutput(
            ok: true,
            title: title,
            output: String(lines.joined(separator: "\n").prefix(8000)),
            detail: "\(symbols.count) results"
        )
    }

    private func formatFileSymbols(_ symbols: [IndexedSymbol], filePath: String) -> ToolOutput {
        var lines: [String] = []
        lines.append("Symbols in \(filePath) (\(symbols.count)):\n")

        // Group: types first, then functions, then properties
        let types = symbols.filter { $0.kind.isType }
        let callables = symbols.filter { $0.kind.isCallable }
        let data = symbols.filter { $0.kind.isDataDeclaration }
        let other = symbols.filter {
            !$0.kind.isType && !$0.kind.isCallable && !$0.kind.isDataDeclaration
        }

        if !types.isEmpty {
            lines.append("Types:")
            for s in types {
                let range = s.endLine > 0 ? "L\(s.line)-\(s.endLine)" : "L\(s.line)"
                let inheritsStr =
                    s.inherits.isEmpty ? "" : " : \(s.inherits.joined(separator: ", "))"
                lines.append("  \(s.kind.rawValue) \(s.name)\(inheritsStr) (\(range))")
            }
            lines.append("")
        }

        if !callables.isEmpty {
            lines.append("Functions/Methods:")
            for s in callables {
                let range = s.endLine > 0 ? "L\(s.line)-\(s.endLine)" : "L\(s.line)"
                let container = s.containerName.map { "\($0)." } ?? ""
                let staticStr = s.isStatic ? "static " : ""
                lines.append("  \(staticStr)\(container)\(s.name) (\(range))")
            }
            lines.append("")
        }

        if !data.isEmpty {
            lines.append("Properties/Constants:")
            for s in data {
                let container = s.containerName.map { "\($0)." } ?? ""
                let staticStr = s.isStatic ? "static " : ""
                lines.append("  \(staticStr)\(s.kind.rawValue) \(container)\(s.name) (L\(s.line))")
            }
            lines.append("")
        }

        if !other.isEmpty {
            lines.append("Other:")
            for s in other {
                lines.append("  \(s.kind.rawValue) \(s.name) (L\(s.line))")
            }
        }

        return ToolOutput(
            ok: true,
            title: "list_symbols: \(filePath)",
            output: String(lines.joined(separator: "\n").prefix(8000)),
            detail: "\(symbols.count) symbols"
        )
    }

    private func formatFileResults(_ files: [FileNode], title: String) -> ToolOutput {
        var lines: [String] = []
        lines.append("Found \(files.count) file(s):\n")

        for file in files {
            let sizeStr = ByteCountFormatter.string(
                fromByteCount: Int64(file.size), countStyle: .file)
            let langStr = file.language != .unknown ? " [\(file.language.rawValue)]" : ""
            lines.append("  \(file.relativePath) (\(sizeStr))\(langStr)")
        }

        return ToolOutput(
            ok: true,
            title: title,
            output: lines.joined(separator: "\n"),
            detail: "\(files.count) files"
        )
    }
}

// MARK: - ToolOutput

/// Internal output model for an index tool.
private struct ToolOutput {
    let ok: Bool
    let title: String
    let output: String
    let detail: String?

    init(ok: Bool, title: String, output: String, detail: String? = nil) {
        self.ok = ok
        self.title = title
        self.output = output
        self.detail = detail
    }
}
