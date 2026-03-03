import Foundation

// MARK: - Reporting and index lifecycle

extension CodebaseIndexTools {
    func executeCodebaseStats() async -> ToolOutput {
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

    func executeDependencyGraph(args: [String: String]) async -> ToolOutput {
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

    func executeListTypes() async -> ToolOutput {
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

    func executeListTests() async -> ToolOutput {
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

    func executeIndexStatus() async -> ToolOutput {
        let summary = await index.summaryText()
        let info = await index.status()

        return ToolOutput(
            ok: true,
            title: "index_status",
            output: summary,
            detail: "\(info.status.rawValue) — \(info.totalSymbols) symbols"
        )
    }

    func executeReindex(
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

    func shouldPerformFullReindex(
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

    func normalizeWorkspacePaths(_ paths: [URL]) -> [String] {
        let values = paths.map { $0.standardizedFileURL.path }
        return normalizeWorkspacePaths(values)
    }

    func normalizeWorkspacePaths(_ paths: [String]) -> [String] {
        var normalized = Set<String>()
        for rawPath in paths {
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let value = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            normalized.insert(value)
        }
        return normalized.sorted()
    }
}
